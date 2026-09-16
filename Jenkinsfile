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

        // ─────────────────────────────────────────────
        // 1. Checkout
        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥 Checking out source code from GitHub...'
                checkout scm
            }
        }

        // ─────────────────────────────────────────────
        // 2. Install Dependencies
        // ─────────────────────────────────────────────
        stage('Install Dependencies') {
            steps {
                echo '🐍 Installing Python dependencies...'

                sh '''
                    python3 -m venv venv
                    ./venv/bin/pip install --upgrade pip
                    ./venv/bin/pip install -r requirements.txt
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 3. Test
        // ─────────────────────────────────────────────
        stage('Test') {
            steps {
                echo '🧪 Running Python compilation test...'

                sh '''
                    ./venv/bin/python -m compileall .
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 4. SonarQube Analysis
        // ─────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                echo '📊 Running SonarQube analysis...'

                withSonarQubeEnv('SonarQube') {
                    script {

                        def scannerHome = tool 'SonarScanner'

                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey=${APP_NAME} \
                                -Dsonar.projectName=${APP_NAME} \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=venv/**,.git/**,**/__pycache__/**
                        """
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 5. SonarQube Quality Gate
        // ─────────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarQube Quality Gate...'

                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ─────────────────────────────────────────────
        // 6. Docker Build
        // ─────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                echo '🐳 Building Docker image...'

                sh '''
                    docker build \
                        -t ${ECR_URI}:${IMAGE_TAG} \
                        -t ${ECR_URI}:latest \
                        .
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 7. Security Scan
        // ─────────────────────────────────────────────
        stage('Security Scan') {
            steps {
                echo '🔒 Scanning Docker image with Trivy...'

                sh '''
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        aquasec/trivy:latest image \
                        --exit-code 0 \
                        --severity HIGH,CRITICAL \
                        --no-progress \
                        ${ECR_URI}:${IMAGE_TAG}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 8. Login to AWS ECR
        // ─────────────────────────────────────────────
        stage('Login to ECR') {
            steps {
                echo '🔐 Logging in to AWS ECR...'

                withAWS(
                    credentials: 'aws-ecr-credentials',
                    region: "${AWS_REGION}"
                ) {
                    sh '''
                        aws ecr get-login-password \
                            --region ${AWS_REGION} | \
                        docker login \
                            --username AWS \
                            --password-stdin \
                            ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────
        // 9. Create ECR Repository
        // ─────────────────────────────────────────────
        stage('Create ECR Repository') {
            steps {
                echo '📦 Checking ECR repository...'

                withAWS(
                    credentials: 'aws-ecr-credentials',
                    region: "${AWS_REGION}"
                ) {
                    sh '''
                        aws ecr describe-repositories \
                            --repository-names ${ECR_REPOSITORY} \
                            --region ${AWS_REGION} \
                        || \
                        aws ecr create-repository \
                            --repository-name ${ECR_REPOSITORY} \
                            --region ${AWS_REGION}
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────
        // 10. Push Docker Image to ECR
        // ─────────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                echo '📤 Pushing Docker image to AWS ECR...'

                withAWS(
                    credentials: 'aws-ecr-credentials',
                    region: "${AWS_REGION}"
                ) {
                    sh '''
                        docker push ${ECR_URI}:${IMAGE_TAG}
                        docker push ${ECR_URI}:latest
                    '''
                }

                echo "✅ Image pushed to ECR: ${ECR_URI}:${IMAGE_TAG}"
            }
        }

        // ─────────────────────────────────────────────
        // 11. Update Kubernetes Manifest
        // ─────────────────────────────────────────────
        stage('Update Deployment Manifest') {
            when {
                branch 'main'
            }

            steps {
                echo '📝 Updating Kubernetes deployment manifest...'

                withCredentials([
                    string(
                        credentialsId: 'github-token',
                        variable: 'GH_TOKEN'
                    )
                ]) {

                    sh '''
                        sed -i \
                            "s|image: .*seclock.*|image: ${ECR_URI}:${IMAGE_TAG}|g" \
                            ${K8S_MANIFEST}

                        git config user.email "jenkins@seclock.ci"
                        git config user.name "Jenkins CI"

                        git add ${K8S_MANIFEST}

                        git commit \
                            -m "ci: update image tag to ${IMAGE_TAG} [skip ci]" \
                            || true

                        git push \
                            https://${GH_TOKEN}@github.com/denitjoseph/seclock.git \
                            HEAD:main
                    '''
                }

                echo '🔄 Kubernetes manifest updated in GitHub.'
                echo '🚀 Argo CD can now synchronize the new image to EKS.'
            }
        }
    }

    // ─────────────────────────────────────────────
    // Post Pipeline
    // ─────────────────────────────────────────────
    post {

        always {
            echo '🧹 Cleaning up workspace and Docker images...'

            script {
                sh '''
                    docker rmi \
                        ${ECR_URI}:${IMAGE_TAG} \
                        ${ECR_URI}:latest \
                        2>/dev/null || true
                '''

                cleanWs()
            }
        }

        success {
            echo "✅ PIPELINE SUCCESS"
            echo "Build Number: ${BUILD_NUMBER}"
            echo "Docker Image: ${ECR_URI}:${IMAGE_TAG}"
        }

        failure {
            echo "❌ PIPELINE FAILED"
            echo "Build Number: ${BUILD_NUMBER}"
            echo "Check the console output for the error."
        }

        unstable {
            echo "⚠️ PIPELINE UNSTABLE"
        }
    }
}
