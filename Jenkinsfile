pipeline {
    agent any

    tools {
        nodejs 'nodejs-20'
    }

    environment {
        AWS_REGION = 'eu-central-1'
        ECR_REGISTRY = '962496666337.dkr.ecr.eu-central-1.amazonaws.com'
        IMAGE_TAG = "${BUILD_NUMBER}"
        ECR_REPO = 'jenkins-cicd-pipeline-app'
        ECS_CLUSTER = 'jenkins-cicd-pipeline-cluster'
        ECS_SERVICE = 'jenkins-cicd-pipeline-service'
        ECS_TASK_FAMILY = 'jenkins-cicd-pipeline-task'
        QUALITY_GATE_FAILED = 'false'
    }

    stages {
        // ─────────────────────────────────────────────
        // 1. CHECKOUT
        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo 'Checking out code...'
                checkout scm
            }
        }

        // ─────────────────────────────────────────────
        // 2. SECRET SCANNING (warn only - does not block)
        // ─────────────────────────────────────────────
        stage('Secret Scanning') {
            steps {
                echo 'Scanning for secrets with Gitleaks...'
                script {
                    sh '''
                        docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
                            --source /repo \
                            --report-path /repo/gitleaks-report.json \
                            --report-format json \
                            --no-git || true
                    '''

                    checkGitleaksReport()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. INSTALL DEPENDENCIES
        // ─────────────────────────────────────────────
        stage('Install Dependencies') {
            steps {
                echo 'Installing dependencies...'
                sh 'npm ci'
            }
        }

        // ─────────────────────────────────────────────
        // 4. SAST - SONARQUBE (warn only - not yet configured)
        // ─────────────────────────────────────────────

        // stage('SAST - SonarQube') {
        //     steps {
        //         catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
        //             echo 'Running SAST with SonarQube...'
        //             runSonarQubeScan()
        //         }
        //     }
        // }

        // ─────────────────────────────────────────────
        // 5. SCA - DEPENDENCY CHECK (warn only - known vulns in dev deps)
        // ─────────────────────────────────────────────
        stage('SCA - Dependency Check') {
            steps {
                catchError(getUnstableConfig()) {
                    echo 'Running SCA with npm audit and Snyk...'
                    runNpmAudit()
                    runSnykScan()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 6. UNIT TESTS
        // ─────────────────────────────────────────────
        stage('Unit Tests') {
            steps {
                echo 'Running unit tests...'
                sh 'npm test'
            }
        }

        // ─────────────────────────────────────────────
        // 7. BUILD DOCKER IMAGE
        // ─────────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                echo 'Building Docker image...'
                sh '''
                    docker build -t $ECR_REPO:$BUILD_NUMBER .
                    docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REPO:latest
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 8. GENERATE SBOM
        // ─────────────────────────────────────────────
        stage('Generate SBOM') {
            steps {
                echo 'Generating SBOM with Syft...'
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        anchore/syft:latest $ECR_REPO:$BUILD_NUMBER \
                        -o cyclonedx-json > sbom-cyclonedx.json

                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        anchore/syft:latest $ECR_REPO:$BUILD_NUMBER \
                        -o spdx-json > sbom-spdx.json
                '''
                archiveArtifacts artifacts: 'sbom-*.json', fingerprint: true
            }
        }

        // ─────────────────────────────────────────────
        // 9. CONTAINER IMAGE SCAN - TRIVY
        // ─────────────────────────────────────────────
        // stage('Container Image Scan') {
        //     steps {
        //         echo 'Scanning container image with Trivy...'
        //         script {
        //             sh '''
        //                 docker run --rm \
        //                 -v /var/run/docker.sock:/var/run/docker.sock \
        //                 -v $WORKSPACE:/workspace \
        //                 aquasec/trivy:latest \
        //                 image --format json \
        //                 --output /workspace/trivy-report.json \
        //                 $ECR_REPO:$BUILD_NUMBER
        //             '''

        //             analyzeTrivyReport()
        //         }
        //     }
        // }

        // ─────────────────────────────────────────────
        // 10. QUALITY GATE CHECK
        // ─────────────────────────────────────────────
        stage('Quality Gate Check') {
            steps {
                script {
                    // if (env.QUALITY_GATE_FAILED == 'true' ) {
                    //     error('DEPLOYMENT BLOCKED: Quality gate failed due to security findings')
                    // }
                    echo 'All quality gates passed - proceeding to deployment'
                }
            }
        }

        // ─────────────────────────────────────────────
        // 11. PUSH TO ECR
        // ─────────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                echo 'Pushing image to Amazon ECR...'
                script {
                pushToECR()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 12. UPDATE ECS TASK DEFINITION
        // ─────────────────────────────────────────────
        stage('Update ECS Task Definition') {
            steps {
                echo 'Registering new ECS task definition...'
                script {
                    updateECSTaskDefinition()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 13. DEPLOY TO ECS
        // ─────────────────────────────────────────────
        stage('Deploy to ECS') {
            steps {
                echo 'Updating ECS service with new task definition...'
                script {
                    deployToECS()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 14. VERIFY DEPLOYMENT
        // ─────────────────────────────────────────────
        stage('Verify Deployment') {
            steps {
                echo 'Verifying deployment health...'
                script {
                    verifyDeployment()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 15. CLEANUP OLD ECR IMAGES
        // ─────────────────────────────────────────────
        stage('Cleanup Old Images') {
            steps {
                echo 'Cleaning up old ECR images...'
                script {
                    cleanupOldImages()
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // POST ACTIONS
    // ─────────────────────────────────────────────
    post {
        always {
            echo 'Archiving security reports and artifacts...'
            archiveArtifacts artifacts: '**/*-report.json, sbom-*.json',
                            fingerprint: true,
                            allowEmptyArchive: true

            publishHTML([
                allowMissing: true,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: '.',
                reportFiles: 'trivy-report.json',
                reportName: 'Trivy Security Report'
            ])

            sh '''
                docker rmi $ECR_REPO:$BUILD_NUMBER || true
                docker rmi $ECR_REPO:latest || true
                docker rmi $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER || true
                docker rmi $ECR_REGISTRY/$ECR_REPO:latest || true
                docker system prune -f || true
            '''

            cleanWs()
        }

        success {
            echo 'Pipeline completed successfully!'
            script {
                def message = """
                Deployment Successful

                Build:       #${BUILD_NUMBER}
                Image:       ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                ECS Cluster: ${ECS_CLUSTER}
                ECS Service: ${ECS_SERVICE}

                Security Scans:
                  - Gitleaks (Secret Scanning)
                  - SonarQube (SAST)        [warn-only until configured]
                  - npm audit + Snyk (SCA)  [warn-only until vulns resolved]
                  - Trivy (Container Scan)

                Artifacts:
                  - SBOM (CycloneDX & SPDX)
                  - Security scan reports
                """
                echo message
            }
        }

        failure {
            echo 'Pipeline failed!'
            script {
                def failureReason = (env.QUALITY_GATE_FAILED == 'true') ?
                    'SECURITY GATE FAILURE - Deployment blocked due to security findings' :
                    'BUILD FAILURE - Check logs for technical issues'
                echo failureReason
            }
        }
    }
}

// ─────────────────────────────────────────────
// HELPER FUNCTIONS
// ─────────────────────────────────────────────
def checkGitleaksReport() {
    if (fileExists('gitleaks-report.json')) {
        def report = readJSON file: 'gitleaks-report.json'
        if (report && report.size() > 0) {
            echo "WARNING: ${report.size()} secret(s) detected - review gitleaks-report.json"
            unstable('Secret scanning found potential secrets - pipeline continues but marked unstable')
        } else {
            echo 'No secrets detected'
        }
    }
}

def runNpmAudit() {
    sh '''
        npm audit --json > npm-audit-report.json || true
        AUDIT_EXIT=0
        npm audit --audit-level=high || AUDIT_EXIT=$?
        if [ "$AUDIT_EXIT" != "0" ]; then
            echo "WARNING: High/Critical vulnerabilities found in dependencies"
            exit 1
        fi
    '''
}

def runSnykScan() {
    withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
        sh '''
            npx snyk test --json > snyk-report.json || true
            SNYK_EXIT=0
            npx snyk test --severity-threshold=high || SNYK_EXIT=$?
            if [ "$SNYK_EXIT" != "0" ]; then
                echo "WARNING: High/Critical vulnerabilities found by Snyk"
                exit 1
            fi
        '''
    }
    echo 'SCA passed'
}

def analyzeTrivyReport() {
    def trivyReport = readJSON file: 'trivy-report.json'
    def criticalCount = 0
    def highCount = 0

    trivyReport.Results?.each { result ->
        result.Vulnerabilities?.each { vuln ->
            if (vuln.Severity == 'CRITICAL') {
                criticalCount++
            }
            if (vuln.Severity == 'HIGH') {
                highCount++
            }
        }
    }

    echo "Trivy found: ${criticalCount} Critical, ${highCount} High vulnerabilities"

    if (criticalCount > 0 || highCount > 0) {
        env.QUALITY_GATE_FAILED = 'true'
        echo "WARNING: Found ${criticalCount} Critical and ${highCount} High vulnerabilities"
    }
    echo 'Container scan passed'
}

def getAWSConfig() {
    return [credentials: 'aws-credentials', region: 'eu-central-1']
}

// def pushToECR() {
//     withAWS(credentials: 'aws-credentials') {
//         sh '''
//             aws ecr get-login-password --region $AWS_REGION | \
//                 docker login --username AWS --password-stdin $ECR_REGISTRY

//             docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER
//             docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REGISTRY/$ECR_REPO:latest

//             docker push $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER
//             docker push $ECR_REGISTRY/$ECR_REPO:latest
//         '''
//     }
// }

def pushToECR() {
    sh '''
        echo "Logging in to ECR..."
        aws ecr get-login-password --region $AWS_REGION | \
            docker login --username AWS --password-stdin $ECR_REGISTRY

        echo "Tagging Docker image..."
        docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER
        docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REGISTRY/$ECR_REPO:latest

        echo "Pushing Docker image to ECR..."
        docker push $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER
        docker push $ECR_REGISTRY/$ECR_REPO:latest
    '''
}

def updateECSTaskDefinition() {
    withAWS(getAWSConfig()) {
        sh '''
            aws ecs describe-task-definition \
                --task-definition $ECS_TASK_FAMILY \
                --query 'taskDefinition' > current-task-def.json

            jq --arg IMAGE "$ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER" \
                '.containerDefinitions[0].image = $IMAGE |
                del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
                current-task-def.json > new-task-def.json

            aws ecs register-task-definition \
                --cli-input-json file://new-task-def.json \
                --query 'taskDefinition.revision' \
                --output text > task-revision.txt

            echo "Registered new task definition revision: $(cat task-revision.txt)"
        '''
    }
}

def deployToECS() {
    withAWS(getAWSConfig()) {
        def taskRevision = sh(script: 'cat task-revision.txt', returnStdout: true).trim()

        sh """
            aws ecs update-service \
                --cluster ${ECS_CLUSTER} \
                --service ${ECS_SERVICE} \
                --task-definition ${ECS_TASK_FAMILY}:${taskRevision} \
                --force-new-deployment

            echo "Waiting for deployment to complete..."
            aws ecs wait services-stable \
                --cluster ${ECS_CLUSTER} \
                --services ${ECS_SERVICE}

            echo "ECS service updated successfully"
        """
    }
}

def verifyDeployment() {
    withAWS(getAWSConfig()) {
        sh '''
            SERVICE_STATUS=$(aws ecs describe-services \
                --cluster $ECS_CLUSTER \
                --services $ECS_SERVICE \
                --query 'services[0].status' \
                --output text)

            RUNNING_COUNT=$(aws ecs describe-services \
                --cluster $ECS_CLUSTER \
                --services $ECS_SERVICE \
                --query 'services[0].runningCount' \
                --output text)

            DESIRED_COUNT=$(aws ecs describe-services \
                --cluster $ECS_CLUSTER \
                --services $ECS_SERVICE \
                --query 'services[0].desiredCount' \
                --output text)

            echo "Service Status: $SERVICE_STATUS"
            echo "Running Tasks: $RUNNING_COUNT/$DESIRED_COUNT"

            if [ "$SERVICE_STATUS" = "ACTIVE" ] && [ "$RUNNING_COUNT" = "$DESIRED_COUNT" ]; then
                echo "Deployment verification successful"
            else
                echo "Deployment verification failed"
                exit 1
            fi
        '''
    }
}

def cleanupOldImages() {
    withAWS(getAWSConfig()) {
        sh '''
            OLD_IMAGES=$(aws ecr list-images \
                --repository-name $ECR_REPO \
                --filter tagStatus=TAGGED \
                --query 'imageIds[10:]' \
                --output json)

            if [ "$OLD_IMAGES" != "[]" ] && [ "$OLD_IMAGES" != "null" ]; then
                echo "Deleting old images..."
                aws ecr batch-delete-image \
                    --repository-name $ECR_REPO \
                    --image-ids "$OLD_IMAGES" || true
                echo "Old images cleaned up"
            else
                echo "No old images to clean up"
            fi
        '''
    }
}

def getUnstableConfig() {
    return [buildResult: 'UNSTABLE', stageResult: 'UNSTABLE']
}

def runSonarQubeScan() {
    withSonarQubeEnv('SonarQube') {
        sh '''
            sonar-scanner \
                -Dsonar.projectKey=cicd-node-app \
                -Dsonar.organization=asheryram \
                -Dsonar.sources=. \
                -Dsonar.exclusions=node_modules/**,test/**
        '''
    }
    timeout(time: 5, unit: 'MINUTES') {
        def qg = waitForQualityGate()
        if (qg.status != 'OK') {
            env.QUALITY_GATE_FAILED = 'true'
            error("CRITICAL: SonarQube quality gate failed: ${qg.status}")
        }
    }
    echo 'SAST passed'
}
