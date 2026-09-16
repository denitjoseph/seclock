pipeline {
    agent any

    environment {
        APP_NAME       = 'seclock'
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '208805232757'
        ECR_REGISTRY   = '208805232757.dkr.ecr.ap-south-1.amazonaws.com'
        IMAGE_NAME     = "${ECR_REGISTRY}/seclock"
        AWS_CREDS      = 'aws-ecr-credentials'
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

        // ── 2. Docker Build ──────────────────────────────────────────────────
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

        // ── 3. Security Scan (Trivy) ─────────────────────────────────────────
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

        // ── 4. Push to AWS ECR ───────────────────────────────────────────────
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

        // ── 5. Update K8s Manifest for ArgoCD GitOps ────────────────────────
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
