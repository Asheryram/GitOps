// ═══════════════════════════════════════════════════════════════════════════════
// VERSION 3: ALWAYS GREEN + SINGLE FINAL SLACK SECURITY REPORT
//
// BEHAVIOUR:
//   - Pipeline NEVER fails or goes unstable due to security findings
//   - All stages always run to completion
//   - All findings are collected silently throughout the pipeline
//   - One final Slack report sent at the end summarising all findings
//
// PIPELINE ONLY TURNS RED FOR:
//   - SSM config missing
//   - Checkout failure
//   - npm ci failure
//   - Unit test failure
//   - Docker build failure
//   - ECR push failure
//   - ECS deploy failure
//
// SLACK ROUTING:
//   - Any security findings       -> #app-alerts
//   - Pipeline / infra error      -> #devops-alerts
//   - All clear + deployed        -> #app-alerts
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

        // Findings collected per scanner — set in each stage
        FINDINGS_GITLEAKS    = ''
        FINDINGS_SONAR       = ''
        FINDINGS_NPM         = ''
        FINDINGS_SNYK        = ''
        FINDINGS_TRIVY       = ''

        // Highest severity seen across all scanners
        HAS_CRITICAL         = 'false'
        HAS_HIGH             = 'false'
        HAS_MEDIUM           = 'false'

        // Pipeline error tracking (infra/tool failures only)
        PIPELINE_ERROR       = 'false'
        PIPELINE_ERROR_STAGE = ''
        PIPELINE_ERROR_MSG   = ''
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
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Configure Environment'
                        env.PIPELINE_ERROR_MSG   = 'No SSM parameters found at /jenkins/cicd/ — run terraform apply'
                        error(env.PIPELINE_ERROR_MSG)
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

                    env.GIT_COMMIT_SHORT  = sh(script: 'git rev-parse --short HEAD 2>/dev/null || echo N/A', returnStdout: true).trim()
                    env.GIT_COMMIT_AUTHOR = sh(script: 'git log -1 --pretty=format:"%an" 2>/dev/null || echo N/A', returnStdout: true).trim()

                    echo "Environment configured — ${env.GIT_COMMIT_SHORT} by ${env.GIT_COMMIT_AUTHOR}"
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
                        checkout scm
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Checkout'
                        env.PIPELINE_ERROR_MSG   = "Checkout failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. SECRET SCANNING
        //    Findings collected — pipeline continues regardless
        // ─────────────────────────────────────────────
        stage('Secret Scanning') {
            steps {
                script {
                    try {
                        sh '''
                            docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
                                --source /repo \
                                --report-path /repo/gitleaks-report.json \
                                --report-format json \
                                --no-git || true
                        '''

                        if (fileExists('gitleaks-report.json')) {
                            def report = readJSON file: 'gitleaks-report.json'
                            if (report && report.size() > 0) {
                                env.HAS_CRITICAL = 'true'
                                def lines = report.take(10).collect { leak ->
                                    "    - [${leak.RuleID}] ${leak.File} at line ${leak.StartLine}"
                                }.join('\n')
                                def more = report.size() > 10 ? "\n    ...and ${report.size() - 10} more. See gitleaks-report.json" : ''
                                env.FINDINGS_GITLEAKS = "GITLEAKS [CRITICAL] — ${report.size()} secret(s) found\n${lines}${more}\n    ACTION: Revoke all exposed credentials immediately and purge from git history."
                                echo "[GITLEAKS] ${report.size()} secret(s) found"
                            } else {
                                env.FINDINGS_GITLEAKS = 'GITLEAKS [PASS] — No secrets found'
                                echo '[GITLEAKS] Clean'
                            }
                        } else {
                            env.FINDINGS_GITLEAKS = 'GITLEAKS [WARN] — No report generated, scanner may have failed'
                            echo '[GITLEAKS] No report found'
                        }
                    } catch (err) {
                        env.FINDINGS_GITLEAKS = "GITLEAKS [ERROR] — Scanner failed: ${err.message}"
                        echo "[GITLEAKS] Error: ${err.message}"
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
                        sh 'npm ci'
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Install Dependencies'
                        env.PIPELINE_ERROR_MSG   = "npm ci failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 5. SAST - SONARQUBE
        //    Findings collected — pipeline continues regardless
        // ─────────────────────────────────────────────
        stage('SAST - SonarQube') {
            steps {
                script {
                    try {
                        withSonarQubeEnv('SonarQube') {
                            sh '''
                                sonar-scanner \
                                    -Dsonar.projectKey=$SONAR_PROJECT \
                                    -Dsonar.organization=$SONAR_ORG \
                                    -Dsonar.qualitygate.wait=false
                            '''
                        }
                        timeout(time: 5, unit: 'MINUTES') {
                            def qg = waitForQualityGate()
                            if (qg.status == 'ERROR') {
                                env.HAS_CRITICAL   = 'true'
                                env.FINDINGS_SONAR = "SONARQUBE [CRITICAL] — Quality gate ERROR\n    - Fix all Blocker and Critical issues before next release\n    - Review findings at the SonarQube dashboard"
                            } else if (qg.status != 'OK') {
                                env.HAS_HIGH       = 'true'
                                env.FINDINGS_SONAR = "SONARQUBE [HIGH] — Quality gate ${qg.status}\n    - Address Major and Minor issues before next release\n    - Review findings at the SonarQube dashboard"
                            } else {
                                env.FINDINGS_SONAR = 'SONARQUBE [PASS] — Quality gate passed'
                            }
                            echo "[SONAR] Gate: ${qg.status}"
                        }
                    } catch (err) {
                        env.FINDINGS_SONAR = "SONARQUBE [ERROR] — Scanner failed: ${err.message}"
                        echo "[SONAR] Error: ${err.message}"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 6. SCA - NPM AUDIT
        //    Findings collected — pipeline continues regardless
        // ─────────────────────────────────────────────
        stage('SCA - npm audit') {
            steps {
                script {
                    try {
                        sh 'npm audit --json > npm-audit-report.json || true'
                        def report   = readJSON file: 'npm-audit-report.json'
                        def vulns    = report.vulnerabilities ?: [:]

                        def critical = vulns.findAll { k, v -> v.severity == 'critical' }
                        def high     = vulns.findAll { k, v -> v.severity == 'high' }
                        def medium   = vulns.findAll { k, v -> v.severity == 'moderate' }
                        def low      = vulns.findAll { k, v -> v.severity == 'low' }

                        if (critical.size() > 0) env.HAS_CRITICAL = 'true'
                        if (high.size() > 0)     env.HAS_HIGH     = 'true'
                        if (medium.size() > 0)   env.HAS_MEDIUM   = 'true'

                        def total = critical.size() + high.size() + medium.size() + low.size()

                        if (total == 0) {
                            env.FINDINGS_NPM = 'NPM AUDIT [PASS] — No vulnerabilities found'
                        } else {
                            def severity = critical.size() > 0 ? 'CRITICAL' : (high.size() > 0 ? 'HIGH' : 'MEDIUM')
                            def lines    = []
                            lines << "    Counts — Critical: ${critical.size()}  High: ${high.size()}  Medium: ${medium.size()}  Low: ${low.size()}"
                            critical.take(3).each { k, v ->
                                def fix = v.fixAvailable ? 'npm audit fix --force' : 'no fix available'
                                lines << "    - [CRITICAL] ${k} — ${fix}"
                            }
                            high.take(3).each { k, v ->
                                def fix = v.fixAvailable ? 'npm audit fix' : 'no fix available'
                                lines << "    - [HIGH] ${k} — ${fix}"
                            }
                            if ((critical.size() + high.size()) > 6) {
                                lines << "    ...see npm-audit-report.json for full list"
                            }
                            env.FINDINGS_NPM = "NPM AUDIT [${severity}] — ${total} issue(s) found\n${lines.join('\n')}"
                        }
                        echo "[NPM] Critical:${critical.size()} High:${high.size()} Medium:${medium.size()} Low:${low.size()}"
                    } catch (err) {
                        env.FINDINGS_NPM = "NPM AUDIT [ERROR] — Scanner failed: ${err.message}"
                        echo "[NPM] Error: ${err.message}"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 7. SCA - SNYK
        //    Findings collected — pipeline continues regardless
        // ─────────────────────────────────────────────
        stage('SCA - Snyk') {
            steps {
                script {
                    try {
                        withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                            sh 'npx snyk test --json > snyk-report.json || true'
                            def report   = readJSON file: 'snyk-report.json'
                            def vulns    = report.vulnerabilities ?: []

                            def critical = vulns.findAll { it.severity == 'critical' }
                            def high     = vulns.findAll { it.severity == 'high' }
                            def medium   = vulns.findAll { it.severity == 'medium' }
                            def low      = vulns.findAll { it.severity == 'low' }

                            if (critical.size() > 0) env.HAS_CRITICAL = 'true'
                            if (high.size() > 0)     env.HAS_HIGH     = 'true'
                            if (medium.size() > 0)   env.HAS_MEDIUM   = 'true'

                            def total = critical.size() + high.size() + medium.size() + low.size()

                            if (total == 0) {
                                env.FINDINGS_SNYK = 'SNYK [PASS] — No vulnerabilities found'
                            } else {
                                def severity = critical.size() > 0 ? 'CRITICAL' : (high.size() > 0 ? 'HIGH' : 'MEDIUM')
                                def lines    = []
                                lines << "    Counts — Critical: ${critical.size()}  High: ${high.size()}  Medium: ${medium.size()}  Low: ${low.size()}"
                                critical.take(3).each { v ->
                                    def cve = v.identifiers?.CVE?.join(', ') ?: 'No CVE'
                                    def fix = v.fixedIn ? "upgrade to ${v.fixedIn[0]}" : 'no fix available'
                                    lines << "    - [CRITICAL] ${v.packageName}@${v.version} — ${v.title} (${cve}) — ${fix}"
                                }
                                high.take(3).each { v ->
                                    def fix = v.fixedIn ? "upgrade to ${v.fixedIn[0]}" : 'no fix available'
                                    lines << "    - [HIGH] ${v.packageName}@${v.version} — ${v.title} — ${fix}"
                                }
                                if ((critical.size() + high.size()) > 6) {
                                    lines << "    ...see snyk-report.json for full list"
                                }
                                env.FINDINGS_SNYK = "SNYK [${severity}] — ${total} issue(s) found\n${lines.join('\n')}"
                            }
                            echo "[SNYK] Critical:${critical.size()} High:${high.size()} Medium:${medium.size()} Low:${low.size()}"
                        }
                    } catch (err) {
                        env.FINDINGS_SNYK = "SNYK [ERROR] — Scanner failed: ${err.message}"
                        echo "[SNYK] Error: ${err.message}"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 8. UNIT TESTS
        // ─────────────────────────────────────────────
        stage('Unit Tests') {
            steps {
                script {
                    try {
                        sh 'npm test'
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Unit Tests'
                        env.PIPELINE_ERROR_MSG   = "Unit tests failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 9. BUILD DOCKER IMAGE
        // ─────────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                script {
                    try {
                        sh '''
                            docker build -t $ECR_REPO:$BUILD_NUMBER .
                            docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REPO:latest
                        '''
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Build Docker Image'
                        env.PIPELINE_ERROR_MSG   = "Docker build failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 10. GENERATE SBOM
        // ─────────────────────────────────────────────
        stage('Generate SBOM') {
            steps {
                script {
                    try {
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
                        echo "[SBOM] Warning — generation failed: ${err.message}. Continuing pipeline."
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 11. CONTAINER IMAGE SCAN - TRIVY
        //     Findings collected — pipeline continues regardless
        // ─────────────────────────────────────────────
        stage('Container Image Scan') {
            steps {
                script {
                    try {
                        sh '''
                            docker run --rm \
                                -v /var/run/docker.sock:/var/run/docker.sock \
                                -v $WORKSPACE:/workspace \
                                aquasec/trivy:latest \
                                image --format json \
                                --output /workspace/trivy-report.json \
                                $ECR_REPO:$BUILD_NUMBER
                        '''

                        def report        = readJSON file: 'trivy-report.json'
                        def criticalCount = 0
                        def highCount     = 0
                        def mediumCount   = 0
                        def lowCount      = 0

                        report.Results?.each { result ->
                            result.Vulnerabilities?.each { vuln ->
                                switch (vuln.Severity) {
                                    case 'CRITICAL': criticalCount++; break
                                    case 'HIGH':     highCount++;     break
                                    case 'MEDIUM':   mediumCount++;   break
                                    case 'LOW':      lowCount++;      break
                                }
                            }
                        }

                        if (criticalCount > 0) env.HAS_CRITICAL = 'true'
                        if (highCount > 0)     env.HAS_HIGH     = 'true'
                        if (mediumCount > 0)   env.HAS_MEDIUM   = 'true'

                        def total = criticalCount + highCount + mediumCount + lowCount

                        if (total == 0) {
                            env.FINDINGS_TRIVY = 'TRIVY [PASS] — No vulnerabilities found'
                        } else {
                            def severity = criticalCount > 0 ? 'CRITICAL' : (highCount > 0 ? 'HIGH' : 'MEDIUM')
                            def lines    = []
                            lines << "    Counts — Critical: ${criticalCount}  High: ${highCount}  Medium: ${mediumCount}  Low: ${lowCount}"

                            def shown = 0
                            report.Results?.each { result ->
                                if (shown >= 5) return
                                result.Vulnerabilities?.findAll { it.Severity in ['CRITICAL', 'HIGH'] }?.each { vuln ->
                                    if (shown >= 5) return
                                    def fix = vuln.FixedVersion ? "upgrade to ${vuln.FixedVersion}" : 'no fix available'
                                    lines << "    - [${vuln.Severity}] ${vuln.PkgName}@${vuln.InstalledVersion} — ${vuln.VulnerabilityID} — ${fix}"
                                    shown++
                                }
                            }
                            if (total > 5) {
                                lines << "    ...see trivy-report.json for full list"
                            }
                            env.FINDINGS_TRIVY = "TRIVY [${severity}] — ${total} issue(s) found\n${lines.join('\n')}"
                        }
                        echo "[TRIVY] Critical:${criticalCount} High:${highCount} Medium:${mediumCount} Low:${lowCount}"
                    } catch (err) {
                        env.FINDINGS_TRIVY = "TRIVY [ERROR] — Scanner failed: ${err.message}"
                        echo "[TRIVY] Error: ${err.message}"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 12. PUSH TO ECR
        // ─────────────────────────────────────────────
        stage('Push to ECR') {
            steps {
                script {
                    try {
                        sh '''
                            aws ecr get-login-password --region $AWS_REGION | \
                                docker login --username AWS --password-stdin $ECR_REGISTRY
                            docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER
                            docker tag $ECR_REPO:$BUILD_NUMBER $ECR_REGISTRY/$ECR_REPO:latest
                            docker push $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER
                            docker push $ECR_REGISTRY/$ECR_REPO:latest
                        '''
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Push to ECR'
                        env.PIPELINE_ERROR_MSG   = "ECR push failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
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

                            echo "Registered revision: $(cat task-revision.txt)"
                        '''
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Update ECS Task Definition'
                        env.PIPELINE_ERROR_MSG   = "ECS task definition update failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
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
                        def taskRevision = sh(script: 'cat task-revision.txt', returnStdout: true).trim()
                        sh """
                            aws ecs update-service \
                                --cluster ${env.ECS_CLUSTER} \
                                --service ${env.ECS_SERVICE} \
                                --task-definition ${env.ECS_TASK_FAMILY}:${taskRevision} \
                                --force-new-deployment

                            aws ecs wait services-stable \
                                --cluster ${env.ECS_CLUSTER} \
                                --services ${env.ECS_SERVICE}

                            echo "ECS service updated successfully"
                        """
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Deploy to ECS'
                        env.PIPELINE_ERROR_MSG   = "ECS deployment failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
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
                        sh '''
                            RUNNING=$(aws ecs describe-services \
                                --cluster $ECS_CLUSTER --services $ECS_SERVICE \
                                --query 'services[0].runningCount' --output text)
                            DESIRED=$(aws ecs describe-services \
                                --cluster $ECS_CLUSTER --services $ECS_SERVICE \
                                --query 'services[0].desiredCount' --output text)
                            echo "Running: $RUNNING / Desired: $DESIRED"
                            [ "$RUNNING" = "$DESIRED" ] || exit 1
                        '''
                    } catch (err) {
                        env.PIPELINE_ERROR       = 'true'
                        env.PIPELINE_ERROR_STAGE = 'Verify Deployment'
                        env.PIPELINE_ERROR_MSG   = "Deployment verification failed: ${err.message}"
                        error(env.PIPELINE_ERROR_MSG)
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 16. CLEANUP OLD ECR IMAGES
        // ─────────────────────────────────────────────
        stage('Cleanup Old Images') {
            steps {
                script {
                    def keepCount = env.IMAGES_TO_KEEP ?: '5'
                    sh """
                        OLD_IMAGES=\$(aws ecr list-images \
                            --repository-name \$ECR_REPO \
                            --filter tagStatus=TAGGED \
                            --query 'imageIds[${keepCount}:]' \
                            --output json)
                        if [ "\$OLD_IMAGES" != "[]" ] && [ "\$OLD_IMAGES" != "null" ]; then
                            aws ecr batch-delete-image \
                                --repository-name \$ECR_REPO \
                                --image-ids "\$OLD_IMAGES" || true
                            echo "Old images cleaned up"
                        else
                            echo "No old images to clean up"
                        fi
                    """
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST — single final Slack report, always runs
    // ═══════════════════════════════════════════════════════════════════════════
    post {
        always {
            script {
                def commitShort  = env.GIT_COMMIT_SHORT  ?: 'N/A'
                def commitAuthor = env.GIT_COMMIT_AUTHOR ?: 'N/A'

                // ── Determine channel and colour ──────────────────────────────
                def channel, color, headline

                if (env.PIPELINE_ERROR == 'true') {
                    channel  = env.SLACK_DEVOPS_CHANNEL
                    color    = 'danger'
                    headline = "[PIPELINE ERROR] Build #${BUILD_NUMBER} failed at stage: ${env.PIPELINE_ERROR_STAGE}"
                } else if (env.HAS_CRITICAL == 'true') {
                    channel  = env.SLACK_APP_CHANNEL
                    color    = 'danger'
                    headline = "[SECURITY REPORT] Build #${BUILD_NUMBER} — CRITICAL findings detected"
                } else if (env.HAS_HIGH == 'true') {
                    channel  = env.SLACK_APP_CHANNEL
                    color    = 'warning'
                    headline = "[SECURITY REPORT] Build #${BUILD_NUMBER} — HIGH findings detected"
                } else if (env.HAS_MEDIUM == 'true') {
                    channel  = env.SLACK_APP_CHANNEL
                    color    = 'warning'
                    headline = "[SECURITY REPORT] Build #${BUILD_NUMBER} — MEDIUM findings detected"
                } else {
                    channel  = env.SLACK_APP_CHANNEL
                    color    = 'good'
                    headline = "[SECURITY REPORT] Build #${BUILD_NUMBER} — All scans passed"
                }

                // ── Scan results block ────────────────────────────────────────
                def scanResults = [
                    env.FINDINGS_GITLEAKS ?: 'GITLEAKS  — not run',
                    env.FINDINGS_SONAR    ?: 'SONARQUBE — not run',
                    env.FINDINGS_NPM      ?: 'NPM AUDIT — not run',
                    env.FINDINGS_SNYK     ?: 'SNYK      — not run',
                    env.FINDINGS_TRIVY    ?: 'TRIVY     — not run',
                ].join('\n\n')

                // ── Pipeline error block ──────────────────────────────────────
                def errorBlock = env.PIPELINE_ERROR == 'true' ? """
Pipeline Error Detail:
${env.PIPELINE_ERROR_MSG}
See console logs: ${env.BUILD_URL}console
""" : ''

                // ── Final Slack message ───────────────────────────────────────
                slackSend(
                    channel: channel,
                    color: color,
                    message: """
${headline}

Build:      #${BUILD_NUMBER}
Branch:     ${env.GIT_BRANCH ?: 'N/A'}
Commit:     ${commitShort} by ${commitAuthor}
Image:      ${env.ECR_REGISTRY ?: 'N/A'}/${env.ECR_REPO ?: 'N/A'}:${env.IMAGE_TAG}
Duration:   ${currentBuild.durationString}

─────────────────────────────────────
Security Scan Results
─────────────────────────────────────
${scanResults}
${errorBlock}
─────────────────────────────────────
Reports
─────────────────────────────────────
Gitleaks : ${env.BUILD_URL}artifact/gitleaks-report.json
npm audit: ${env.BUILD_URL}artifact/npm-audit-report.json
Snyk     : ${env.BUILD_URL}artifact/snyk-report.json
Trivy    : ${env.BUILD_URL}artifact/trivy-report.json

Build    : ${env.BUILD_URL}
Logs     : ${env.BUILD_URL}console
                    """.stripIndent()
                )
            }

            archiveArtifacts artifacts: '**/*-report.json, sbom-*.json',
                             fingerprint: true,
                             allowEmptyArchive: true

            sh '''
                docker rmi $ECR_REPO:$BUILD_NUMBER || true
                docker rmi $ECR_REPO:latest || true
                docker rmi $ECR_REGISTRY/$ECR_REPO:$BUILD_NUMBER || true
                docker rmi $ECR_REGISTRY/$ECR_REPO:latest || true
                docker system prune -f || true
            '''

            cleanWs()
        }
    }
}