pipeline {
    agent any

    environment {
        APP_NAME       = 'seclock'
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '208805232757'
        ECR_REGISTRY   = '208805232757.dkr.ecr.ap-south-1.amazonaws.com'
        IMAGE_NAME     = "${ECR_REGISTRY}/seclock"
        AWS_CREDS      = 'aws-ecr-credentials'                   // Jenkins credential ID (used in ECR stage)
        SONAR_HOST     = 'http://localhost:9000'                 // SonarQube URL
        PYTHON_VERSION = '3'
        PORT           = '8000'
        GIT_REPO       = 'denitjoseph/seclock'
        K8S_MANIFEST   = 'k8s/deployment.yaml'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
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
                    python3 -m venv .venv
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

        // ── 5. SonarQube Analysis ────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                echo '📊 Running SonarQube code quality scan...'
                sh '''
                    . .venv/bin/activate
                    pip install coverage --quiet
                    coverage run -m pytest test_e2e.py --junitxml=test-results.xml || true
                    coverage xml -o coverage.xml || true
                '''
                withSonarQubeEnv('SonarQube') {
                    withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                        sh """
                            sonar-scanner \\
                                -Dsonar.projectKey=${APP_NAME} \\
                                -Dsonar.projectName='Seclock' \\
                                -Dsonar.projectVersion=1.0 \\
                                -Dsonar.sources=. \\
                                -Dsonar.exclusions='**/.venv/**,**/__pycache__/**,**/test_*.py' \\
                                -Dsonar.python.coverage.reportPaths=coverage.xml \\
                                -Dsonar.python.xunit.reportPath=test-results.xml \\
                                -Dsonar.host.url=${SONAR_HOST} \\
                                -Dsonar.login=\${SONAR_TOKEN}
                        """
                    }
                }
            }
        }

        // ── 6. SonarQube Quality Gate ────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarQube Quality Gate...'
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ── 7. Docker Build ──────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                echo '🐳 Building Docker image...'
                script {
                    def shortCommit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG    = "${env.BUILD_NUMBER}-${shortCommit}"
                    env.IMAGE_LATEST = "${IMAGE_NAME}:latest"
                    env.IMAGE_TAGGED = "${IMAGE_NAME}:${env.IMAGE_TAG}"

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

        // ── 8. Security Scan (Trivy) ─────────────────────────────────────────
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

        // ── 9. Push to AWS ECR ───────────────────────────────────────────────
        stage('Push to AWS ECR') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                    branch 'release/*'
                }
            }
            steps {
                echo '📤 Authenticating with AWS ECR and pushing image...'
                withAWS(credentials: 'aws-ecr-credentials', region: "${AWS_REGION}") {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        # Create ECR repository if it doesn't exist
                        aws ecr describe-repositories --repository-names ${APP_NAME} \
                            --region ${AWS_REGION} || \
                        aws ecr create-repository --repository-name ${APP_NAME} \
                            --region ${AWS_REGION} \
                            --image-scanning-configuration scanOnPush=true \
                            --image-tag-mutability MUTABLE

                        docker push ${env.IMAGE_TAGGED}
                        docker push ${env.IMAGE_LATEST}
                    """
                }
                echo "✅ Image pushed: ${env.IMAGE_TAGGED}"
            }
        }

        // ── 10. Update K8s Manifest for ArgoCD GitOps ───────────────────────
        stage('Update Deployment Manifest') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                }
            }
            steps {
                echo '📝 Updating deployment.yaml image tag for ArgoCD...'
                script {
                    sh """
                        sed -i 's|image: .*seclock.*|image: ${env.IMAGE_TAGGED}|g' ${K8S_MANIFEST}
                    """
                    withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
                        sh """
                            git config user.email "jenkins@seclock.ci"
                            git config user.name "Jenkins CI"
                            git add ${K8S_MANIFEST}
                            git commit -m "ci: update image tag to ${env.IMAGE_TAG} [skip ci]" || true
                            git push https://\${GH_TOKEN}@github.com/denitjoseph/seclock.git HEAD:${env.BRANCH_NAME}
                        """
                    }
                }
                echo '🔄 ArgoCD will auto-sync the new image tag to the cluster.'
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
