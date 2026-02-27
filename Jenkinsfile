// ═══════════════════════════════════════════════════════════════════════════════
// VERSION 2: FAIL-FAST + SMART SLACK NOTIFICATIONS + DETAILED VULNERABILITY REPORTS
//
// SECURITY SCAN BEHAVIOUR:
//   Critical findings  → FAIL pipeline    → Slack to #app-alerts
//   High/Medium/Low    → UNSTABLE pipeline → Slack to #app-alerts
//   Pipeline errors    → FAIL pipeline    → Slack to #devops-alerts
//   All passed         → SUCCESS          → Slack to both channels
//
// SLACK MESSAGE INCLUDES:
//   - Commit SHA and author
//   - Total vulnerability counts per severity
//   - Affected package names with recommended fix versions
//   - Links to specific scan reports
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
        IMAGE_TAG            = "${BUILD_NUMBER}"
        SLACK_APP_CHANNEL    = '#app-alerts'
        SLACK_DEVOPS_CHANNEL = '#devops-alerts'
        FAILURE_TYPE         = ''
        FAILURE_STAGE        = ''
        FAILURE_REASON       = ''
        FAILURE_SUMMARY      = ''
        VULN_COUNTS          = ''
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Configure Environment'
                        env.FAILURE_REASON  = 'No SSM parameters found at /jenkins/cicd/ — run terraform apply'
                        env.FAILURE_SUMMARY = '• Check SSM Parameter Store in AWS console\n• Verify IAM role has ssm:GetParametersByPath permission\n• Run terraform apply to create missing parameters'
                        throw new Exception(env.FAILURE_REASON)
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

                    // Capture commit metadata for Slack messages
                    env.GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short HEAD 2>/dev/null || echo N/A', returnStdout: true).trim()
                    env.GIT_COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=format:"%an" 2>/dev/null || echo N/A', returnStdout: true).trim()

                    echo "Environment configured from SSM (1 API call)"
                    echo "AWS_REGION: ${env.AWS_REGION}"
                    echo "ECR_REPO: ${env.ECR_REPO}"
                    echo "ECR_REGISTRY: ${env.ECR_REGISTRY}"
                    echo "ECS_CLUSTER: ${env.ECS_CLUSTER}"
                    echo "ECS_SERVICE: ${env.ECS_SERVICE}"
                    echo "Commit: ${env.GIT_COMMIT_SHORT} by ${env.GIT_COMMIT_AUTHOR}"
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Checkout'
                        env.FAILURE_REASON  = "Failed to checkout source code: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check SCM configuration and credentials in Jenkins\n• Verify repository URL and branch name are correct'
                        throw new Exception(env.FAILURE_REASON)
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
                            env.FAILURE_TYPE    = 'PIPELINE'
                            env.FAILURE_STAGE   = 'Secret Scanning'
                            env.FAILURE_REASON  = "Gitleaks scanner error: ${err.message}"
                            env.FAILURE_SUMMARY = '• Check Docker is running and Gitleaks image is accessible\n• Verify Docker socket permissions on Jenkins agent'
                        }
                        throw err
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Install Dependencies'
                        env.FAILURE_REASON  = "npm ci failed — check package.json or network: ${err.message}"
                        env.FAILURE_SUMMARY = '• Verify package.json and package-lock.json are valid and committed\n• Check network connectivity to npm registry\n• Try running npm ci locally to reproduce'
                        throw new Exception(env.FAILURE_REASON)
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
                            env.FAILURE_TYPE    = 'PIPELINE'
                            env.FAILURE_STAGE   = 'SAST - SonarQube'
                            env.FAILURE_REASON  = "SonarQube scanner error: ${err.message}"
                            env.FAILURE_SUMMARY = '• Check SonarQube server connection and credentials in Jenkins\n• Verify sonar-scanner is installed on the agent\n• Check sonar.projectKey matches SonarQube project'
                        }
                        throw err
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
                            env.FAILURE_TYPE    = 'PIPELINE'
                            env.FAILURE_STAGE   = 'SCA - Dependency Check'
                            env.FAILURE_REASON  = "SCA scanner error: ${err.message}"
                            env.FAILURE_SUMMARY = '• Check Snyk token credential in Jenkins\n• Verify network access to Snyk API\n• Ensure npx is available on the agent'
                        }
                        throw err
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Unit Tests'
                        env.FAILURE_REASON  = "Unit tests failed: ${err.message}"
                        env.FAILURE_SUMMARY = '• Review test output in console logs\n• Fix failing tests before retrying\n• Run npm test locally to reproduce'
                        throw new Exception(env.FAILURE_REASON)
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Build Docker Image'
                        env.FAILURE_REASON  = "Docker build failed: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check Dockerfile syntax\n• Verify Docker daemon is running on agent\n• Check base image is accessible from agent'
                        throw new Exception(env.FAILURE_REASON)
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Generate SBOM'
                        env.FAILURE_REASON  = "Syft SBOM generation failed: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check Docker socket access on agent\n• Verify Syft image is accessible'
                        throw new Exception(env.FAILURE_REASON)
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
                            env.FAILURE_TYPE    = 'PIPELINE'
                            env.FAILURE_STAGE   = 'Container Image Scan'
                            env.FAILURE_REASON  = "Trivy scanner error: ${err.message}"
                            env.FAILURE_SUMMARY = '• Check Docker socket access on agent\n• Verify Trivy image is accessible'
                        }
                        throw err
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Push to ECR'
                        env.FAILURE_REASON  = "Failed to push image to ECR: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check IAM role has ecr:PutImage and ecr:GetAuthorizationToken permissions\n• Verify ECR repository exists in the correct region\n• Check Docker login to ECR succeeded'
                        throw new Exception(env.FAILURE_REASON)
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Update ECS Task Definition'
                        env.FAILURE_REASON  = "Failed to register ECS task definition: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check IAM role has ecs:RegisterTaskDefinition permission\n• Verify task family name matches existing definition\n• Check jq is installed on the agent'
                        throw new Exception(env.FAILURE_REASON)
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Deploy to ECS'
                        env.FAILURE_REASON  = "ECS deployment failed or service did not stabilize: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check ECS service events in AWS console\n• Verify task has enough CPU/memory resources\n• Check container health check configuration\n• Review CloudWatch logs for container startup errors'
                        throw new Exception(env.FAILURE_REASON)
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
                        env.FAILURE_TYPE    = 'PIPELINE'
                        env.FAILURE_STAGE   = 'Verify Deployment'
                        env.FAILURE_REASON  = "Deployment verification failed — running count does not match desired: ${err.message}"
                        env.FAILURE_SUMMARY = '• Check ECS task stopped reason in AWS console\n• Review application logs in CloudWatch\n• Verify security group and VPC configuration\n• Check target group health in load balancer'
                        throw new Exception(env.FAILURE_REASON)
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

            // cleanWs() moved to cleanup block — runs AFTER Slack notifications
            // so env vars (FAILURE_TYPE, FAILURE_REASON etc.) are still available
        }

        // ─────────────────────────────────────────────
        // CLEANUP — runs last, after all other post blocks including Slack
        // ─────────────────────────────────────────────
        cleanup {
            cleanWs()
        }

        // ─────────────────────────────────────────────
        // SUCCESS → both channels
        // ─────────────────────────────────────────────
        success {
            script {
                def msg = """
✅ *Deployment Successful*

*Build:*        #${BUILD_NUMBER}
*Branch:*       ${env.GIT_BRANCH ?: 'N/A'}
*Commit:*       '${env.GIT_COMMIT_SHORT ?: 'N/A'}' by ${env.GIT_COMMIT_AUTHOR ?: 'N/A'}
*Image:*        ${env.ECR_REGISTRY}/${env.ECR_REPO}:${env.IMAGE_TAG}
*ECS Cluster:*  ${env.ECS_CLUSTER}
*ECS Service:*  ${env.ECS_SERVICE}
*Duration:*     ${currentBuild.durationString}

*Security Scans — All Passed:*
✔ Gitleaks  — No secrets found
✔ SonarQube — Quality gate passed
✔ npm audit — No critical CVEs
✔ Snyk      — No critical CVEs
✔ Trivy     — No critical CVEs

*Reports:*
• <${env.BUILD_URL}artifact/trivy-report.json|Trivy Report>
• <${env.BUILD_URL}artifact/npm-audit-report.json|npm Audit Report>
• <${env.BUILD_URL}artifact/snyk-report.json|Snyk Report>
• <${env.BUILD_URL}artifact/gitleaks-report.json|Gitleaks Report>
• <${env.BUILD_URL}Trivy_20Security_20Report|Trivy HTML Report>

<${env.BUILD_URL}|View Build>
                """.stripIndent()

                slackSend(channel: env.SLACK_APP_CHANNEL,    color: 'good', message: msg)
                slackSend(channel: env.SLACK_DEVOPS_CHANNEL, color: 'good', message: msg)
            }
        }

        // ─────────────────────────────────────────────
        // UNSTABLE → non-critical app findings → #app-alerts only
        // ─────────────────────────────────────────────
        unstable {
            script {
                slackSend(
                    channel: env.SLACK_APP_CHANNEL,
                    color: 'warning',
                    message: """
⚠️ *Build UNSTABLE — Non-Critical Security Findings*

*Build:*        #${BUILD_NUMBER}
*Branch:*       ${env.GIT_BRANCH ?: 'N/A'}
*Commit:*       '${env.GIT_COMMIT_SHORT ?: 'N/A'}' by ${env.GIT_COMMIT_AUTHOR ?: 'N/A'}
*Duration:*     ${currentBuild.durationString}
*Stage:*        ${env.FAILURE_STAGE ?: 'See report'}
*Issue Type:*   🟡 Application Issue (non-critical)
*Summary:*      ${env.FAILURE_REASON ?: 'High/Medium/Low severity findings detected'}

${env.VULN_COUNTS ? '*Vulnerability Counts:*\n' + env.VULN_COUNTS : ''}

*Findings (top 5):*
${env.FAILURE_SUMMARY ?: '_No detailed summary available — check scan reports_'}

*Reports:*
• <${env.BUILD_URL}artifact/trivy-report.json|Trivy Report>
• <${env.BUILD_URL}artifact/npm-audit-report.json|npm Audit Report>
• <${env.BUILD_URL}artifact/snyk-report.json|Snyk Report>
• <${env.BUILD_URL}Trivy_20Security_20Report|Trivy HTML Report>

Deployment proceeded but findings require attention.
Fix before next release.

<${env.BUILD_URL}|View Build> | <${env.BUILD_URL}console|View Logs>
                    """.stripIndent()
                )
            }
        }

        // ─────────────────────────────────────────────
        // FAILURE → route by FAILURE_TYPE
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
                def reportLinks = isAppIssue ? """
*Reports:*
• <${env.BUILD_URL}artifact/trivy-report.json|Trivy Report>
• <${env.BUILD_URL}artifact/npm-audit-report.json|npm Audit Report>
• <${env.BUILD_URL}artifact/snyk-report.json|Snyk Report>
• <${env.BUILD_URL}artifact/gitleaks-report.json|Gitleaks Report>
• <${env.BUILD_URL}Trivy_20Security_20Report|Trivy HTML Report>""" : """
*Reports:*
• <${env.BUILD_URL}console|Full Console Log>"""

                slackSend(
                    channel: channel,
                    color: 'danger',
                    message: """
❌ *Deployment FAILED*

*Build:*        #${BUILD_NUMBER}
*Branch:*       ${env.GIT_BRANCH ?: 'N/A'}
*Commit:*       '${env.GIT_COMMIT_SHORT ?: 'N/A'}' by ${env.GIT_COMMIT_AUTHOR ?: 'N/A'}
*Duration:*     ${currentBuild.durationString}
*Failed Stage:* ${env.FAILURE_STAGE ?: 'Unknown'}
*Issue Type:*   ${issueLabel}
*Reason:*       ${env.FAILURE_REASON ?: 'Check console logs for details'}

${env.VULN_COUNTS ? '*Vulnerability Counts:*\n' + env.VULN_COUNTS : ''}

*Findings / Details (top 5):*
${env.FAILURE_SUMMARY ?: '_No detailed summary available — check console logs_'}

${actionLine}
${reportLinks}

<${env.BUILD_URL}|View Build> | <${env.BUILD_URL}console|View Logs>
                    """.stripIndent()
                )
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

def checkGitleaksReport() {
    if (fileExists('gitleaks-report.json')) {
        def report = readJSON file: 'gitleaks-report.json'
        if (report && report.size() > 0) {
            def details = report.take(5).collect { leak ->
                "• `${leak.RuleID}` in `${leak.File}` at line ${leak.StartLine}"
            }.join('\n')
            def more = report.size() > 5 ? "\n_...and ${report.size() - 5} more. See gitleaks-report.json_" : ''

            env.FAILURE_TYPE    = 'APP_CRITICAL'
            env.FAILURE_STAGE   = 'Secret Scanning'
            env.FAILURE_REASON  = "${report.size()} secret(s) detected in source code"
            env.VULN_COUNTS     = "🔴 Secrets found: ${report.size()}"
            env.FAILURE_SUMMARY = details + more
            throw new Exception(env.FAILURE_REASON)
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
            env.FAILURE_TYPE    = 'APP_CRITICAL'
            env.FAILURE_STAGE   = 'SAST - SonarQube'
            env.FAILURE_REASON  = "Quality gate status: ERROR — critical code issues must be fixed"
            env.VULN_COUNTS     = "🔴 SonarQube Gate: ERROR"
            env.FAILURE_SUMMARY = "• Quality gate returned ERROR status\n• Fix all Blocker and Critical issues\n• Review full findings at the SonarQube dashboard"
            throw new Exception(env.FAILURE_REASON)
        } else if (qg.status != 'OK') {
            env.FAILURE_TYPE    = 'APP_UNSTABLE'
            env.FAILURE_STAGE   = 'SAST - SonarQube'
            env.FAILURE_REASON  = "Quality gate status: ${qg.status} — non-critical issues detected"
            env.VULN_COUNTS     = "🟡 SonarQube Gate: ${qg.status}"
            env.FAILURE_SUMMARY = "• Quality gate returned ${qg.status} status\n• Address Major and Minor issues before next release\n• Review findings at the SonarQube dashboard"
            unstable(env.FAILURE_REASON)
        } else {
            echo 'SonarQube SAST passed'
        }
    }
}

def runNpmAudit() {
    sh 'npm audit --json > npm-audit-report.json || true'

    // Check CRITICAL CVEs → FAIL
    def criticalExit = sh(script: 'npm audit --audit-level=critical', returnStatus: true)
    if (criticalExit != 0) {
        def report       = readJSON file: 'npm-audit-report.json'
        def vulns        = report.vulnerabilities ?: [:]
        def criticalList = vulns.findAll { k, v -> v.severity == 'critical' }
        def details      = criticalList.take(5).collect { k, v ->
            def fixAvail = v.fixAvailable ? "fix: `npm audit fix --force`" : "no fix available"
            "• `${k}` — CRITICAL — ${fixAvail}"
        }.join('\n')
        def more = criticalList.size() > 5 ? "\n_...and ${criticalList.size() - 5} more. See npm-audit-report.json_" : ''

        env.FAILURE_TYPE    = 'APP_CRITICAL'
        env.FAILURE_STAGE   = 'SCA - npm audit'
        env.FAILURE_REASON  = "${criticalList.size()} CRITICAL CVEs found by npm audit"
        env.VULN_COUNTS     = "🔴 Critical: ${criticalList.size()} | 🟠 High: ${vulns.findAll { k, v -> v.severity == 'high' }.size()} | 🟡 Medium: ${vulns.findAll { k, v -> v.severity == 'moderate' }.size()}"
        env.FAILURE_SUMMARY = details + more
        throw new Exception(env.FAILURE_REASON)
    }

    // Check HIGH CVEs → UNSTABLE
    def highExit = sh(script: 'npm audit --audit-level=high', returnStatus: true)
    if (highExit != 0) {
        def report    = readJSON file: 'npm-audit-report.json'
        def vulns     = report.vulnerabilities ?: [:]
        def highList  = vulns.findAll { k, v -> v.severity == 'high' }
        def details   = highList.take(5).collect { k, v ->
            def fixAvail = v.fixAvailable ? "fix: `npm audit fix`" : "no fix available"
            "• `${k}` — HIGH — ${fixAvail}"
        }.join('\n')
        def more = highList.size() > 5 ? "\n_...and ${highList.size() - 5} more. See npm-audit-report.json_" : ''

        env.FAILURE_TYPE    = 'APP_UNSTABLE'
        env.FAILURE_STAGE   = 'SCA - npm audit'
        env.FAILURE_REASON  = "${highList.size()} High CVEs found by npm audit"
        env.VULN_COUNTS     = "🟠 High: ${highList.size()} | 🟡 Medium: ${vulns.findAll { k, v -> v.severity == 'moderate' }.size()}"
        env.FAILURE_SUMMARY = details + more
        unstable(env.FAILURE_REASON)
    } else {
        echo 'npm audit passed'
    }
}

def runSnykScan() {
    withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
        sh 'npx snyk test --json > snyk-report.json || true'

        // Check CRITICAL CVEs → FAIL
        def criticalExit = sh(script: 'npx snyk test --severity-threshold=critical', returnStatus: true)
        if (criticalExit != 0) {
            def report       = readJSON file: 'snyk-report.json'
            def vulns        = report.vulnerabilities ?: []
            def criticalList = vulns.findAll { it.severity == 'critical' }
            def details      = criticalList.take(5).collect { v ->
                def cve      = v.identifiers?.CVE?.join(', ') ?: 'No CVE'
                def fixVer   = v.fixedIn ? "fix: upgrade to ${v.fixedIn[0]}" : "no fix available"
                "• `${v.packageName}@${v.version}` — ${v.title} (${cve}) — ${fixVer}"
            }.join('\n')
            def more = criticalList.size() > 5 ? "\n_...and ${criticalList.size() - 5} more. See snyk-report.json_" : ''

            env.FAILURE_TYPE    = 'APP_CRITICAL'
            env.FAILURE_STAGE   = 'SCA - Snyk'
            env.FAILURE_REASON  = "${criticalList.size()} CRITICAL CVEs found by Snyk"
            env.VULN_COUNTS     = "🔴 Critical: ${criticalList.size()} | 🟠 High: ${vulns.findAll { it.severity == 'high' }.size()} | 🟡 Medium: ${vulns.findAll { it.severity == 'medium' }.size()}"
            env.FAILURE_SUMMARY = details + more
            throw new Exception(env.FAILURE_REASON)
        }

        // Check HIGH CVEs → UNSTABLE
        def highExit = sh(script: 'npx snyk test --severity-threshold=high', returnStatus: true)
        if (highExit != 0) {
            def report    = readJSON file: 'snyk-report.json'
            def vulns     = report.vulnerabilities ?: []
            def highList  = vulns.findAll { it.severity == 'high' }
            def details   = highList.take(5).collect { v ->
                def fixVer = v.fixedIn ? "fix: upgrade to ${v.fixedIn[0]}" : "no fix available"
                "• `${v.packageName}@${v.version}` — ${v.title} — ${fixVer}"
            }.join('\n')
            def more = highList.size() > 5 ? "\n_...and ${highList.size() - 5} more. See snyk-report.json_" : ''

            env.FAILURE_TYPE    = 'APP_UNSTABLE'
            env.FAILURE_STAGE   = 'SCA - Snyk'
            env.FAILURE_REASON  = "${highList.size()} High CVEs found by Snyk"
            env.VULN_COUNTS     = "🟠 High: ${highList.size()} | 🟡 Medium: ${vulns.findAll { it.severity == 'medium' }.size()}"
            env.FAILURE_SUMMARY = details + more
            unstable(env.FAILURE_REASON)
        } else {
            echo 'Snyk scan passed'
        }
    }
}

def analyzeTrivyReport() {
    def trivyReport   = readJSON file: 'trivy-report.json'
    def criticalCount = 0
    def highCount     = 0
    def mediumCount   = 0
    def lowCount      = 0
    def criticalVulns = []
    def highVulns     = []

    trivyReport.Results?.each { result ->
        result.Vulnerabilities?.each { vuln ->
            if (vuln.Severity == 'CRITICAL') {
                criticalCount++
                def fixVer = vuln.FixedVersion ? "fix: upgrade to ${vuln.FixedVersion}" : "no fix available"
                criticalVulns << "• `${vuln.PkgName}@${vuln.InstalledVersion}` — ${vuln.VulnerabilityID} — ${fixVer}"
            }
            if (vuln.Severity == 'HIGH') {
                highCount++
                def fixVer = vuln.FixedVersion ? "fix: upgrade to ${vuln.FixedVersion}" : "no fix available"
                highVulns << "• `${vuln.PkgName}@${vuln.InstalledVersion}` — ${vuln.VulnerabilityID} — ${fixVer}"
            }
            if (vuln.Severity == 'MEDIUM') mediumCount++
            if (vuln.Severity == 'LOW')    lowCount++
        }
    }

    echo "Trivy found: ${criticalCount} Critical, ${highCount} High, ${mediumCount} Medium, ${lowCount} Low"

    if (criticalCount > 0) {
        def details = criticalVulns.take(5).join('\n')
        def more    = criticalCount > 5 ? "\n_...and ${criticalCount - 5} more. See trivy-report.json_" : ''

        env.FAILURE_TYPE    = 'APP_CRITICAL'
        env.FAILURE_STAGE   = 'Container Image Scan'
        env.FAILURE_REASON  = "${criticalCount} CRITICAL CVEs found in container image"
        env.VULN_COUNTS     = "🔴 Critical: ${criticalCount} | 🟠 High: ${highCount} | 🟡 Medium: ${mediumCount} | ⚪ Low: ${lowCount}"
        env.FAILURE_SUMMARY = details + more
        throw new Exception(env.FAILURE_REASON)
    } else if (highCount > 0 || mediumCount > 0) {
        def details = highVulns.take(5).join('\n')
        def more    = highCount > 5 ? "\n_...and ${highCount - 5} more. See trivy-report.json_" : ''

        env.FAILURE_TYPE    = 'APP_UNSTABLE'
        env.FAILURE_STAGE   = 'Container Image Scan'
        env.FAILURE_REASON  = "${highCount} High and ${mediumCount} Medium CVEs found in container image"
        env.VULN_COUNTS     = "🟠 High: ${highCount} | 🟡 Medium: ${mediumCount} | ⚪ Low: ${lowCount}"
        env.FAILURE_SUMMARY = details + more
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
    sh '''
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
    '''
}
