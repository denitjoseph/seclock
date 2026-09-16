pipeline {

    agent any

    environment {
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '208805232757'
        ECR_REPOSITORY = 'seclock'
        IMAGE_TAG      = "${BUILD_NUMBER}"
        ECR_URI        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    python3 -m venv venv
                    ./venv/bin/pip install --upgrade pip
                    ./venv/bin/pip install -r requirements.txt
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    ./venv/bin/python -m compileall .
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    withSonarQubeEnv('SonarQube') {
                        script {
                            def scannerHome = tool 'SonarScanner'

                            sh """
                                ${scannerHome}/bin/sonar-scanner \
                                    -Dsonar.projectKey=seclock \
                                    -Dsonar.projectName=seclock \
                                    -Dsonar.sources=. \
                                    -Dsonar.token=\${SONAR_TOKEN}
                            """
                        }
                    }
                }
            }
        }

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

        stage('Push to ECR') {
            steps {
                sh '''
                    docker push ${ECR_URI}:${IMAGE_TAG}
                    docker push ${ECR_URI}:latest
                '''
            }
        }
    }

    post {
        success {
            echo 'CI pipeline completed successfully.'
        }

        failure {
            echo 'CI pipeline failed.'
        }
    }
}
