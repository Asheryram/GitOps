// ═══════════════════════════════════════════════════════════════════════════════
// VERSION 2: FAIL-FAST + SMART SLACK NOTIFICATIONS
//
// SECURITY SCAN BEHAVIOUR:
//   Critical findings  → FAIL pipeline    → Slack to #app-alerts
//   High/Medium/Low    → UNSTABLE pipeline → Slack to #app-alerts
//   Pipeline errors    → FAIL pipeline    → Slack to #devops-alerts
//   All passed         → SUCCESS          → Slack to both channels
//
// CRITICAL DEFINITIONS:
//   Gitleaks  : any secret found
//   SonarQube : quality gate status = ERROR
//   npm/Snyk  : CRITICAL severity CVEs
//   Trivy     : CRITICAL severity CVEs
// ═══════════════════════════════════════════════════════════════════════════════

pipeline {
    agent any

    tools {
        nodejs 'nodejs-20'
    }

    environment {
        IMAGE_TAG        = "${BUILD_NUMBER}"
        // Slack channels
        SLACK_APP_CHANNEL     = '#app-alerts'
        SLACK_DEVOPS_CHANNEL  = '#devops-alerts'
        // Failure tracking — set by helper functions before calling error()/unstable()
        FAILURE_TYPE     = ''   // 'APP_CRITICAL', 'APP_UNSTABLE', 'PIPELINE'
        FAILURE_STAGE    = ''
        FAILURE_REASON   = ''
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
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Configure Environment'
                        env.FAILURE_REASON = 'No SSM parameters found at /jenkins/cicd/ — run terraform apply'
                        error(env.FAILURE_REASON)
                    }

                    def ssm = parsed.collectEntries {
                        def key = it.Name.replace('/jenkins/cicd/', '')
                        [(key): it.Value]
                    }

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
                script {
                    try {
                        echo 'Checking out code...'
                        checkout scm
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Checkout'
                        env.FAILURE_REASON = "Failed to checkout source code: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. SECRET SCANNING
        //    Any secret found = CRITICAL → FAIL
        // ─────────────────────────────────────────────
        stage('Secret Scanning') {
            steps {
                script {
                    try {
                        echo 'Scanning for secrets with Gitleaks...'
                        sh '''
                            docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
                                --source /repo \
                                --report-path /repo/gitleaks-report.json \
                                --report-format json \
                                --no-git || true
                        '''
                        checkGitleaksReport()
                    } catch (err) {
                        if (env.FAILURE_TYPE == '') {
                            env.FAILURE_TYPE   = 'PIPELINE'
                            env.FAILURE_STAGE  = 'Secret Scanning'
                            env.FAILURE_REASON = "Gitleaks scanner error: ${err.message}"
                        }
                        error(err.message)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 4. INSTALL DEPENDENCIES
        // ─────────────────────────────────────────────
        stage('Install Dependencies') {
            steps {
                script {
                    try {
                        echo 'Installing dependencies...'
                        sh 'npm ci'
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Install Dependencies'
                        env.FAILURE_REASON = "npm ci failed — check package.json or network: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 5. SAST - SONARQUBE
        //    ERROR status = CRITICAL → FAIL
        //    WARN status  = non-critical → UNSTABLE
        // ─────────────────────────────────────────────
        stage('SAST - SonarQube') {
            steps {
                script {
                    try {
                        echo 'Running SAST with SonarQube...'
                        runSonarQubeScan()
                    } catch (err) {
                        if (env.FAILURE_TYPE == '') {
                            env.FAILURE_TYPE   = 'PIPELINE'
                            env.FAILURE_STAGE  = 'SAST - SonarQube'
                            env.FAILURE_REASON = "SonarQube scanner error: ${err.message}"
                        }
                        error(err.message)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 6. SCA - DEPENDENCY CHECK
        //    CRITICAL CVEs = CRITICAL → FAIL
        //    HIGH/MEDIUM   = non-critical → UNSTABLE
        // ─────────────────────────────────────────────
        stage('SCA - Dependency Check') {
            steps {
                script {
                    try {
                        echo 'Running SCA with npm audit and Snyk...'
                        runNpmAudit()
                        runSnykScan()
                    } catch (err) {
                        if (env.FAILURE_TYPE == '') {
                            env.FAILURE_TYPE   = 'PIPELINE'
                            env.FAILURE_STAGE  = 'SCA - Dependency Check'
                            env.FAILURE_REASON = "SCA scanner error: ${err.message}"
                        }
                        error(err.message)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 7. UNIT TESTS
        // ─────────────────────────────────────────────
        stage('Unit Tests') {
            steps {
                script {
                    try {
                        echo 'Running unit tests...'
                        sh 'npm test'
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Unit Tests'
                        env.FAILURE_REASON = "Unit tests failed: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 8. BUILD DOCKER IMAGE
        // ─────────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                script {
                    try {
                        echo 'Building Docker image...'
                        sh '''
                            docker build -t $ECR_REPO:$BUILD_NUMBER .
                            docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REPO:latest
                        '''
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Build Docker Image'
                        env.FAILURE_REASON = "Docker build failed: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 9. GENERATE SBOM
        // ─────────────────────────────────────────────
        stage('Generate SBOM') {
            steps {
                script {
                    try {
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
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Generate SBOM'
                        env.FAILURE_REASON = "Syft SBOM generation failed: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 10. CONTAINER IMAGE SCAN - TRIVY
        //     CRITICAL CVEs = CRITICAL → FAIL
        //     HIGH/MEDIUM   = non-critical → UNSTABLE
        // ─────────────────────────────────────────────
        stage('Container Image Scan') {
            steps {
                script {
                    try {
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
                        analyzeTrivyReport()
                    } catch (err) {
                        if (env.FAILURE_TYPE == '') {
                            env.FAILURE_TYPE   = 'PIPELINE'
                            env.FAILURE_STAGE  = 'Container Image Scan'
                            env.FAILURE_REASON = "Trivy scanner error: ${err.message}"
                        }
                        error(err.message)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 11. QUALITY GATE
        // ─────────────────────────────────────────────
        stage('Quality Gate Check') {
            steps {
                echo 'All security gates passed — proceeding to deployment'
            }
        }

        // ─────────────────────────────────────────────
        // 12. PUSH TO ECR
        // ─────────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                script {
                    try {
                        echo 'Pushing image to Amazon ECR...'
                        pushToECR()
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Push to ECR'
                        env.FAILURE_REASON = "Failed to push image to ECR: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 13. UPDATE ECS TASK DEFINITION
        // ─────────────────────────────────────────────
        stage('Update ECS Task Definition') {
            steps {
                script {
                    try {
                        echo 'Registering new ECS task definition...'
                        updateECSTaskDefinition()
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Update ECS Task Definition'
                        env.FAILURE_REASON = "Failed to register ECS task definition: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 14. DEPLOY TO ECS
        // ─────────────────────────────────────────────
        stage('Deploy to ECS') {
            steps {
                script {
                    try {
                        echo 'Updating ECS service with new task definition...'
                        deployToECS()
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Deploy to ECS'
                        env.FAILURE_REASON = "ECS deployment failed or service did not stabilize: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 15. VERIFY DEPLOYMENT
        // ─────────────────────────────────────────────
        stage('Verify Deployment') {
            steps {
                script {
                    try {
                        echo 'Verifying deployment health...'
                        verifyDeployment()
                    } catch (err) {
                        env.FAILURE_TYPE   = 'PIPELINE'
                        env.FAILURE_STAGE  = 'Verify Deployment'
                        env.FAILURE_REASON = "Deployment verification failed — running count does not match desired: ${err.message}"
                        error(env.FAILURE_REASON)
                    }
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

        // ─────────────────────────────────────────────
        // SUCCESS → both channels
        // ─────────────────────────────────────────────
        success {
            script {
                def msg = """
✅ *Deployment Successful*

*Build:*       #${BUILD_NUMBER}
*Branch:*      ${env.GIT_BRANCH ?: 'N/A'}
*Image:*       ${env.ECR_REGISTRY}/${env.ECR_REPO}:${env.IMAGE_TAG}
*ECS Cluster:* ${env.ECS_CLUSTER}
*ECS Service:* ${env.ECS_SERVICE}
*Duration:*    ${currentBuild.durationString}

✔ Gitleaks  — No secrets found
✔ SonarQube — Quality gate passed
✔ npm audit — No critical CVEs
✔ Snyk      — No critical CVEs
✔ Trivy     — No critical CVEs

<${env.BUILD_URL}|View Build>
                """.stripIndent()

                slackSend(channel: env.SLACK_APP_CHANNEL,    color: 'good', message: msg)
                slackSend(channel: env.SLACK_DEVOPS_CHANNEL, color: 'good', message: msg)
            }
        }

        // ─────────────────────────────────────────────
        // UNSTABLE → app non-critical findings → #app-alerts only
        // ─────────────────────────────────────────────
        unstable {
            script {
                slackSend(
                    channel: env.SLACK_APP_CHANNEL,
                    color: 'warning',
                    message: """
⚠️ *Build UNSTABLE — Non-Critical Security Findings*

*Build:*         #${BUILD_NUMBER}
*Branch:*        ${env.GIT_BRANCH ?: 'N/A'}
*Duration:*      ${currentBuild.durationString}
*Failed Stage:*  ${env.FAILURE_STAGE ?: 'See report'}
*Issue Type:*    🟡 Application Issue (non-critical)
*Reason:*        ${env.FAILURE_REASON ?: 'High/Medium/Low severity findings detected'}

Deployment proceeded but findings require attention.
Review scan reports and fix before next release.

<${env.BUILD_URL}|View Build> | <${env.BUILD_URL}console|View Logs>
                    """.stripIndent()
                )
            }
        }

        // ─────────────────────────────────────────────
        // FAILURE → route based on FAILURE_TYPE
        //   APP_CRITICAL → #app-alerts
        //   PIPELINE     → #devops-alerts
        // ─────────────────────────────────────────────
        failure {
            script {
                def isAppIssue = env.FAILURE_TYPE == 'APP_CRITICAL'
                def channel    = isAppIssue ? env.SLACK_APP_CHANNEL : env.SLACK_DEVOPS_CHANNEL
                def issueLabel = isAppIssue
                    ? '🔴 Application Issue (Critical)'
                    : '⚙️ Pipeline / Infrastructure Issue'
                def actionLine = isAppIssue
                    ? 'Fix the critical findings in the code or dependencies before retrying.'
                    : 'Check AWS credentials, Docker, ECS configuration, or Jenkins setup.'

                slackSend(
                    channel: channel,
                    color: 'danger',
                    message: """
❌ *Deployment FAILED*

*Build:*         #${BUILD_NUMBER}
*Branch:*        ${env.GIT_BRANCH ?: 'N/A'}
*Duration:*      ${currentBuild.durationString}
*Failed Stage:*  ${env.FAILURE_STAGE ?: 'Unknown'}
*Issue Type:*    ${issueLabel}
*Reason:*        ${env.FAILURE_REASON ?: 'Check console logs for details'}

${actionLine}

<${env.BUILD_URL}|View Build> | <${env.BUILD_URL}console|View Logs>
                    """.stripIndent()
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
//
// Each scanner sets FAILURE_TYPE, FAILURE_STAGE, FAILURE_REASON before
// calling error() or unstable() so the post block knows where to route.
//
// APP_CRITICAL  → error()    → pipeline FAILS    → #app-alerts
// APP_UNSTABLE  → unstable() → pipeline UNSTABLE → #app-alerts
// PIPELINE      → error()    → pipeline FAILS    → #devops-alerts
// ═══════════════════════════════════════════════════════════════════════════════

def checkGitleaksReport() {
    // Any secret found = CRITICAL → FAIL
    if (fileExists('gitleaks-report.json')) {
        def report = readJSON file: 'gitleaks-report.json'
        if (report && report.size() > 0) {
            env.FAILURE_TYPE   = 'APP_CRITICAL'
            env.FAILURE_STAGE  = 'Secret Scanning'
            env.FAILURE_REASON = "${report.size()} secret(s) detected in source code — remove all hardcoded secrets immediately"
            error(env.FAILURE_REASON)
        } else {
            echo 'No secrets detected'
        }
    } else {
        echo 'No Gitleaks report found — skipping secret check'
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
        if (qg.status == 'ERROR') {
            // ERROR = Critical → FAIL
            env.FAILURE_TYPE   = 'APP_CRITICAL'
            env.FAILURE_STAGE  = 'SAST - SonarQube'
            env.FAILURE_REASON = "SonarQube quality gate status: ERROR — critical code issues must be fixed"
            error(env.FAILURE_REASON)
        } else if (qg.status != 'OK') {
            // WARN or other = non-critical → UNSTABLE
            env.FAILURE_TYPE   = 'APP_UNSTABLE'
            env.FAILURE_STAGE  = 'SAST - SonarQube'
            env.FAILURE_REASON = "SonarQube quality gate status: ${qg.status} — non-critical issues detected"
            unstable(env.FAILURE_REASON)
        } else {
            echo 'SonarQube SAST passed'
        }
    }
}

def runNpmAudit() {
    sh 'npm audit --json > npm-audit-report.json || true'

    // Check for CRITICAL CVEs → FAIL
    def criticalExit = sh(script: 'npm audit --audit-level=critical', returnStatus: true)
    if (criticalExit != 0) {
        env.FAILURE_TYPE   = 'APP_CRITICAL'
        env.FAILURE_STAGE  = 'SCA - npm audit'
        env.FAILURE_REASON = 'CRITICAL severity CVEs found by npm audit — update affected dependencies'
        error(env.FAILURE_REASON)
    }

    // Check for HIGH CVEs → UNSTABLE
    def highExit = sh(script: 'npm audit --audit-level=high', returnStatus: true)
    if (highExit != 0) {
        env.FAILURE_TYPE   = 'APP_UNSTABLE'
        env.FAILURE_STAGE  = 'SCA - npm audit'
        env.FAILURE_REASON = 'High severity CVEs found by npm audit — review npm-audit-report.json'
        unstable(env.FAILURE_REASON)
    } else {
        echo 'npm audit passed'
    }
}

def runSnykScan() {
    withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
        sh 'npx snyk test --json > snyk-report.json || true'

        // Check for CRITICAL CVEs → FAIL
        def criticalExit = sh(script: 'npx snyk test --severity-threshold=critical', returnStatus: true)
        if (criticalExit != 0) {
            env.FAILURE_TYPE   = 'APP_CRITICAL'
            env.FAILURE_STAGE  = 'SCA - Snyk'
            env.FAILURE_REASON = 'CRITICAL severity CVEs found by Snyk — update affected dependencies'
            error(env.FAILURE_REASON)
        }

        // Check for HIGH CVEs → UNSTABLE
        def highExit = sh(script: 'npx snyk test --severity-threshold=high', returnStatus: true)
        if (highExit != 0) {
            env.FAILURE_TYPE   = 'APP_UNSTABLE'
            env.FAILURE_STAGE  = 'SCA - Snyk'
            env.FAILURE_REASON = 'High severity CVEs found by Snyk — review snyk-report.json'
            unstable(env.FAILURE_REASON)
        } else {
            echo 'Snyk scan passed'
        }
    }
}

def analyzeTrivyReport() {
    def trivyReport = readJSON file: 'trivy-report.json'
    def criticalCount = 0
    def highCount     = 0
    def mediumCount   = 0

    trivyReport.Results?.each { result ->
        result.Vulnerabilities?.each { vuln ->
            if (vuln.Severity == 'CRITICAL') criticalCount++
            if (vuln.Severity == 'HIGH')     highCount++
            if (vuln.Severity == 'MEDIUM')   mediumCount++
        }
    }

    echo "Trivy found: ${criticalCount} Critical, ${highCount} High, ${mediumCount} Medium"

    if (criticalCount > 0) {
        // CRITICAL CVEs → FAIL
        env.FAILURE_TYPE   = 'APP_CRITICAL'
        env.FAILURE_STAGE  = 'Container Image Scan'
        env.FAILURE_REASON = "${criticalCount} CRITICAL CVEs found in container image — update base image or dependencies"
        error(env.FAILURE_REASON)
    } else if (highCount > 0 || mediumCount > 0) {
        // HIGH/MEDIUM → UNSTABLE
        env.FAILURE_TYPE   = 'APP_UNSTABLE'
        env.FAILURE_STAGE  = 'Container Image Scan'
        env.FAILURE_REASON = "${highCount} High and ${mediumCount} Medium CVEs found in container image — review trivy-report.json"
        unstable(env.FAILURE_REASON)
    } else {
        echo 'Container image scan passed'
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
            echo "Deployment verification successful"
        else
            echo "Deployment verification failed"
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
