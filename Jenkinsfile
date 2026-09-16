pipeline {
    agent any

    environment {
        APP_NAME        = 'seclock'
        IMAGE_NAME      = "seclock/seclock"
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_CREDS    = credentials('dockerhub-credentials')   // Jenkins credential ID
        PYTHON_VERSION  = '3.11'
        PORT            = '8000'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 20, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        // ── 1. Checkout ──────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥 Cloning repository...'
                checkout scm
            }
        }

        // ── 2. Environment Setup ─────────────────────────────────────────────
        stage('Setup Python Environment') {
            steps {
                echo '🐍 Setting up virtual environment...'
                sh '''
                    python${PYTHON_VERSION} -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                    pip install pytest httpx
                '''
            }
        }

        // ── 3. Lint ──────────────────────────────────────────────────────────
        stage('Lint') {
            steps {
                echo '🔍 Running linter...'
                sh '''
                    . .venv/bin/activate
                    pip install flake8 --quiet
                    flake8 . --max-line-length=120 --exclude=.venv,__pycache__ --statistics || true
                '''
            }
        }

        // ── 4. Unit / E2E Tests ──────────────────────────────────────────────
        stage('Test') {
            steps {
                echo '🧪 Running test suite...'
                sh '''
                    . .venv/bin/activate
                    pytest test_e2e.py -v --tb=short --junitxml=test-results.xml
                '''
            }
            post {
                always {
                    junit 'test-results.xml'
                }
            }
        }

        // ── 5. Docker Build ──────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                echo '🐳 Building Docker image...'
                script {
                    def shortCommit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG     = "${env.BUILD_NUMBER}-${shortCommit}"
                    env.IMAGE_LATEST  = "${IMAGE_NAME}:latest"
                    env.IMAGE_TAGGED  = "${IMAGE_NAME}:${env.IMAGE_TAG}"

                    sh """
                        docker build \
                            --tag ${env.IMAGE_TAGGED} \
                            --tag ${env.IMAGE_LATEST} \
                            --label "build=${env.BUILD_NUMBER}" \
                            --label "commit=${shortCommit}" \
                            --label "branch=${env.BRANCH_NAME ?: 'local'}" \
                            .
                    """
                }
            }
        }

        // ── 6. Security Scan (Trivy) ─────────────────────────────────────────
        stage('Security Scan') {
            steps {
                echo '🔒 Scanning image for vulnerabilities...'
                sh """
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        aquasec/trivy:latest image \
                        --exit-code 0 \
                        --severity HIGH,CRITICAL \
                        --no-progress \
                        ${env.IMAGE_TAGGED}
                """
            }
        }

        // ── 7. Push to Registry ──────────────────────────────────────────────
        stage('Push to Registry') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                    branch 'release/*'
                }
            }
            steps {
                echo '📤 Pushing image to Docker Hub...'
                sh """
                    echo \$DOCKER_CREDS_PSW | docker login ${DOCKER_REGISTRY} \
                        -u \$DOCKER_CREDS_USR --password-stdin
                    docker push ${env.IMAGE_TAGGED}
                    docker push ${env.IMAGE_LATEST}
                """
            }
        }

        // ── 8. Deploy (Staging) ──────────────────────────────────────────────
        stage('Deploy to Staging') {
            when { branch 'main' }
            steps {
                echo '🚀 Deploying to staging environment...'
                sh """
                    docker stop ${APP_NAME}-staging 2>/dev/null || true
                    docker rm   ${APP_NAME}-staging 2>/dev/null || true
                    docker run -d \
                        --name ${APP_NAME}-staging \
                        --restart unless-stopped \
                        -p 8080:${PORT} \
                        ${env.IMAGE_TAGGED}
                """
                echo '✅ Staging deployed at http://localhost:8080'
            }
        }

    }

    // ── Post-Pipeline ────────────────────────────────────────────────────────
    post {
        always {
            echo '🧹 Cleaning up workspace...'
            sh 'docker rmi ${IMAGE_TAGGED} ${IMAGE_LATEST} 2>/dev/null || true'
            cleanWs()
        }
        success {
            echo "✅ Pipeline SUCCESS — Build #${env.BUILD_NUMBER} | Image: ${env.IMAGE_TAGGED}"
        }
        failure {
            echo "❌ Pipeline FAILED — Check logs for Build #${env.BUILD_NUMBER}"
        }
        unstable {
            echo "⚠️ Pipeline UNSTABLE — Tests may have partial failures."
        }
    }
}
