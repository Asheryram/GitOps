// ═══════════════════════════════════════════════════════════════════════════════
// VERSION 2: FAIL-FAST
// Any security scan failure immediately fails the build and blocks deployment.
// ═══════════════════════════════════════════════════════════════════════════════

pipeline {
    agent any

    tools {
        nodejs 'nodejs-20'
    }

    environment {
        IMAGE_TAG = "${BUILD_NUMBER}"
    }

    stages {

        // ─────────────────────────────────────────────
        // 1. CONFIGURE ENVIRONMENT
        // ─────────────────────────────────────────────
        stage('Configure Environment') {
            steps {
                script {
                    def params = sh(
                        script: '''aws ssm get-parameters-by-path --path /jenkins/cicd/ \
                               --query 'Parameters[*].{Name:Name,Value:Value}' --output json''',
                        returnStdout: true
                    ).trim()

                    def parsed = readJSON text: params

                    if (!parsed || parsed.size() == 0) {
                        error("No SSM parameters found at /jenkins/cicd/. Run 'terraform apply' to create them.")
                    }

                    def ssm = parsed.collectEntries {
                        def key = it.Name.replace('/jenkins/cicd/', '')
                        [(key): it.Value]
                    }

                    echo "Parsed SSM map: ${ssm}"

                    env.AWS_REGION      = ssm['aws-region']
                    env.ECR_REPO        = ssm['ecr-repo']
                    env.ECS_CLUSTER     = ssm['ecs-cluster']
                    env.ECS_SERVICE     = ssm['ecs-service']
                    env.ECS_TASK_FAMILY = ssm['ecs-task-family']
                    env.SONAR_PROJECT   = ssm['sonar-project']
                    env.SONAR_ORG       = ssm['sonar-org']
                    env.IMAGES_TO_KEEP  = ssm['images-to-keep']
                    env.ECR_REGISTRY    = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim() + ".dkr.ecr.${env.AWS_REGION}.amazonaws.com"

                    echo "Environment configured from SSM (1 API call)"
                    echo "AWS_REGION: ${env.AWS_REGION}"
                    echo "ECR_REPO: ${env.ECR_REPO}"
                    echo "ECR_REGISTRY: ${env.ECR_REGISTRY}"
                    echo "ECS_CLUSTER: ${env.ECS_CLUSTER}"
                    echo "ECS_SERVICE: ${env.ECS_SERVICE}"
                }
            }
        }

        // ─────────────────────────────────────────────
        // 2. CHECKOUT
        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo 'Checking out code...'
                checkout scm
            }
        }

        // ─────────────────────────────────────────────
        // 3. SECRET SCANNING (FAIL-FAST)
        // ─────────────────────────────────────────────
        stage('Secret Scanning') {
            steps {
                echo 'Scanning for secrets with Gitleaks...'
                sh '''
                    docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
                        --source /repo \
                        --report-path /repo/gitleaks-report.json \
                        --report-format json \
                        --no-git || true
                '''
                script {
                    checkGitleaksReport()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 4. INSTALL DEPENDENCIES
        // ─────────────────────────────────────────────
        stage('Install Dependencies') {
            steps {
                echo 'Installing dependencies...'
                sh 'npm ci'
            }
        }

        // ─────────────────────────────────────────────
        // 5. SAST - SONARQUBE (FAIL-FAST)
        // ─────────────────────────────────────────────
        stage('SAST - SonarQube') {
            steps {
                echo 'Running SAST with SonarQube...'
                script {
                    runSonarQubeScan()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 6. SCA - DEPENDENCY CHECK (FAIL-FAST)
        // ─────────────────────────────────────────────
        stage('SCA - Dependency Check') {
            steps {
                echo 'Running SCA with npm audit and Snyk...'
                script {
                    runNpmAudit()
                    runSnykScan()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 7. UNIT TESTS
        // ─────────────────────────────────────────────
        stage('Unit Tests') {
            steps {
                echo 'Running unit tests...'
                sh 'npm test'
            }
        }

        // ─────────────────────────────────────────────
        // 8. BUILD DOCKER IMAGE
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
        // 9. GENERATE SBOM
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
        // 10. CONTAINER IMAGE SCAN - TRIVY (FAIL-FAST)
        // ─────────────────────────────────────────────
        stage('Container Image Scan') {
            steps {
                echo 'Scanning container image with Trivy...'
                sh '''
                    docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v $WORKSPACE:/workspace \
                    aquasec/trivy:latest \
                    image --format json \
                    --output /workspace/trivy-report.json \
                    $ECR_REPO:$BUILD_NUMBER
                '''
                script {
                    analyzeTrivyReport()
                }
            }
        }

        // ─────────────────────────────────────────────
        // 11. QUALITY GATE (FAIL-FAST)
        // ─────────────────────────────────────────────
        stage('Quality Gate Check') {
            steps {
                echo 'Fail-fast mode: all security gates must pass before deployment'
            }
        }

        // ─────────────────────────────────────────────
        // 12. PUSH TO ECR
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
        // 13. UPDATE ECS TASK DEFINITION
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
        // 14. DEPLOY TO ECS
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
        // 15. VERIFY DEPLOYMENT
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
        // 16. CLEANUP OLD ECR IMAGES
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
            echo "Pipeline completed successfully! Build #${BUILD_NUMBER} deployed to ECS."
            script {
                def message = """
                 Deployment Successful (Fail-Fast Mode)

                Build:       #${BUILD_NUMBER}
                Image:       ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                ECS Cluster: ${ECS_CLUSTER}
                ECS Service: ${ECS_SERVICE}

                Security Scans (all passed — no findings blocked deployment):
                  - Gitleaks  (Secret Scanning)
                  - SonarQube (SAST)
                  - npm audit + Snyk (SCA)
                  - Trivy     (Container Scan)

                Artifacts:
                  - SBOM (CycloneDX & SPDX)
                  - Security scan reports
                """
                echo message
            }
        }

        failure {
            echo " Pipeline FAILED — security gate blocked deployment. Review reports before retrying."
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS — FAIL-FAST VARIANTS
// error() stops the pipeline immediately on any finding.
// ═══════════════════════════════════════════════════════════════════════════════

def checkGitleaksReport() {
    if (fileExists('gitleaks-report.json')) {
        def report = readJSON file: 'gitleaks-report.json'
        if (report && report.size() > 0) {
            error(" BLOCKED: ${report.size()} secret(s) detected — fix before deploying. Review gitleaks-report.json")
        } else {
            echo ' No secrets detected'
        }
    } else {
        echo ' No Gitleaks report found — skipping secret check'
    }
}

def runSonarQubeScan() {
    withSonarQubeEnv('SonarQube') {
        sh '''
            sonar-scanner \
                -Dsonar.projectKey=$SONAR_PROJECT \
                -Dsonar.organization=$SONAR_ORG \
                -Dsonar.sources=. \
                -Dsonar.exclusions=node_modules/**,test/**
        '''
    }
    timeout(time: 5, unit: 'MINUTES') {
        def qg = waitForQualityGate()
        if (qg.status != 'OK') {
            error(" BLOCKED: SonarQube quality gate failed: ${qg.status} — fix issues before deploying")
        } else {
            echo ' SAST passed'
        }
    }
}

def runNpmAudit() {
    sh 'npm audit --json > npm-audit-report.json || true'
    def exitCode = sh(script: 'npm audit --audit-level=high', returnStatus: true)
    if (exitCode != 0) {
        error(" BLOCKED: High/Critical vulnerabilities found by npm audit — fix before deploying")
    } else {
        echo ' npm audit passed'
    }
}

def runSnykScan() {
    withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
        sh 'npx snyk test --json > snyk-report.json || true'
        def exitCode = sh(script: 'npx snyk test --severity-threshold=high', returnStatus: true)
        if (exitCode != 0) {
            error(" BLOCKED: High/Critical vulnerabilities found by Snyk — fix before deploying")
        } else {
            echo ' Snyk scan passed'
        }
    }
}

def analyzeTrivyReport() {
    def trivyReport = readJSON file: 'trivy-report.json'
    def criticalCount = 0
    def highCount = 0

    trivyReport.Results?.each { result ->
        result.Vulnerabilities?.each { vuln ->
            if (vuln.Severity == 'CRITICAL') criticalCount++
            if (vuln.Severity == 'HIGH')     highCount++
        }
    }

    echo "Trivy found: ${criticalCount} Critical, ${highCount} High vulnerabilities"

    if (criticalCount > 0 || highCount > 0) {
        error(" BLOCKED: ${criticalCount} Critical and ${highCount} High vulnerabilities found — fix before deploying")
    } else {
        echo ' Container scan passed'
    }
}

// ─────────────────────────────────────────────
// SHARED DEPLOY HELPERS
// ─────────────────────────────────────────────

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

def deployToECS() {
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

def verifyDeployment() {
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
            echo " Deployment verification successful"
        else
            echo " Deployment verification failed"
            exit 1
        fi
    '''
}

def cleanupOldImages() {
    def keepCount = env.IMAGES_TO_KEEP ?: '5'
    sh """
        OLD_IMAGES=\$(aws ecr list-images \
            --repository-name \$ECR_REPO \
            --filter tagStatus=TAGGED \
            --query 'imageIds[${keepCount}:]' \
            --output json)

        if [ "\$OLD_IMAGES" != "[]" ] && [ "\$OLD_IMAGES" != "null" ]; then
            echo "Deleting old images (keeping ${keepCount} most recent)..."
            aws ecr batch-delete-image \
                --repository-name \$ECR_REPO \
                --image-ids "\$OLD_IMAGES" || true
            echo "Old images cleaned up"
        else
            echo "No old images to clean up"
        fi
    """
}
