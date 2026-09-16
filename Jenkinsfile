pipeline {
    agent any

    environment {
        APP_NAME       = 'seclock'
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '208805232757'
        ECR_REPOSITORY = 'seclock'
        IMAGE_TAG      = "${BUILD_NUMBER}"
        ECR_URI        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
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
                checkout scm
            }
        }

        // ── 2. Install Dependencies ──────────────────────────────────────────
        stage('Install Dependencies') {
            steps {
                sh '''
                    python3 -m venv venv
                    ./venv/bin/pip install --upgrade pip
                    ./venv/bin/pip install -r requirements.txt
                '''
            }
        }

        // ── 3. Test ──────────────────────────────────────────────────────────
        stage('Test') {
            steps {
                sh '''
                    ./venv/bin/python -m compileall .
                '''
            }
        }

        // ── 4. SonarQube Analysis ────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    script {
                        def scannerHome = tool 'SonarScanner'
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey=${APP_NAME} \
                                -Dsonar.projectName=${APP_NAME} \
                                -Dsonar.sources=.
                        """
                    }
                }
            }
        }

        // ── 5. Docker Build ──────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                sh '''
                    docker build \
                        -t ${ECR_URI}:${IMAGE_TAG} \
                        -t ${ECR_URI}:latest \
                        .
                '''
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
                        ${ECR_URI}:${IMAGE_TAG}
                """
            }
        }

        // ── 7. Login to ECR ──────────────────────────────────────────────────
        stage('Login to ECR') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        aws ecr get-login-password \
                            --region ${AWS_REGION} | \
                        docker login \
                            --username AWS \
                            --password-stdin ${ECR_URI}
                    '''
                }
            }
        }

        // ── 8. Push to ECR ───────────────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                sh '''
                    docker push ${ECR_URI}:${IMAGE_TAG}
                    docker push ${ECR_URI}:latest
                '''
            }
        }

        // ── 9. Update K8s Manifest for ArgoCD ───────────────────────────────
        stage('Update Deployment Manifest') {
            steps {
                echo '📝 Updating deployment.yaml image tag for ArgoCD...'
                withCredentials([string(credentialsId: 'github-token', variable: 'GH_TOKEN')]) {
                    sh """
                        sed -i 's|image: .*seclock.*|image: ${ECR_URI}:${IMAGE_TAG}|g' ${K8S_MANIFEST}
                        git config user.email "jenkins@seclock.ci"
                        git config user.name "Jenkins CI"
                        git add ${K8S_MANIFEST}
                        git commit -m "ci: update image tag to ${IMAGE_TAG} [skip ci]" || true
                        git push https://\${GH_TOKEN}@github.com/denitjoseph/seclock.git HEAD:main
                    """
                }
                echo '🔄 ArgoCD will auto-sync the new image tag to the cluster.'
            }
        }

    }

    post {
        always {
            echo '🧹 Cleaning up workspace...'
            sh 'docker rmi ${ECR_URI}:${IMAGE_TAG} ${ECR_URI}:latest 2>/dev/null || true'
            cleanWs()
        }
        success {
            echo "✅ Pipeline SUCCESS — Build #${BUILD_NUMBER}"
        }
        failure {
            echo "❌ Pipeline FAILED — Check logs for Build #${BUILD_NUMBER}"
        }
    }
}
