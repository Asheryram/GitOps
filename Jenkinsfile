pipeline {
    agent any
    
    tools {
        nodejs 'nodejs-20'
    }

    environment {
        AWS_ACCOUNT_ID = credentials('aws-account-id')
        AWS_REGION = 'us-east-1'
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPO = 'cicd-node-app'
        IMAGE_TAG = "${BUILD_NUMBER}"
        ECS_CLUSTER = 'cicd-cluster'
        ECS_SERVICE = 'cicd-service'
        ECS_TASK_FAMILY = 'cicd-task'
        QUALITY_GATE_FAILED = 'false'
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out code...'
                checkout scm
            }
        }
        
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
                    
                    if (fileExists('gitleaks-report.json')) {
                        def report = readJSON file: 'gitleaks-report.json'
                        if (report && report.size() > 0) {
                            env.QUALITY_GATE_FAILED = 'true'
                            error("❌ CRITICAL: Secrets detected! Found ${report.size()} secret(s)")
                        }
                    }
                    echo '✅ No secrets detected'
                }
            }
        }
        
        stage('Install Dependencies') {
            steps {
                echo 'Installing dependencies...'
                sh 'npm ci'
            }
        }
        
        stage('SAST - SonarQube') {
            steps {
                echo 'Running SAST with SonarQube...'
                script {
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                            sonar-scanner \
                                -Dsonar.projectKey=cicd-node-app \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=node_modules/**,test/**
                        '''
                    }
                    
                    timeout(time: 5, unit: 'MINUTES') {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            env.QUALITY_GATE_FAILED = 'true'
                            error("❌ CRITICAL: SonarQube quality gate failed: ${qg.status}")
                        }
                    }
                    echo '✅ SAST passed'
                }
            }
        }
        
        stage('SCA - Dependency Check') {
            steps {
                echo 'Running SCA with npm audit and Snyk...'
                script {
                    sh '''
                        npm audit --json > npm-audit-report.json || true
                        npm audit --audit-level=high || AUDIT_EXIT=$?
                        
                        if [ "$AUDIT_EXIT" != "0" ]; then
                            echo "❌ High/Critical vulnerabilities found in dependencies"
                            exit 1
                        fi
                    '''
                    
                    withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                        sh '''
                            npx snyk test --json > snyk-report.json || true
                            npx snyk test --severity-threshold=high || SNYK_EXIT=$?
                            
                            if [ "$SNYK_EXIT" != "0" ]; then
                                echo "❌ High/Critical vulnerabilities found by Snyk"
                                exit 1
                            fi
                        '''
                    }
                    echo '✅ SCA passed'
                }
            }
        }
        
        stage('Unit Tests') {
            steps {
                echo 'Running unit tests...'
                sh 'npm test'
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo 'Building Docker image...'
                sh """
                    docker build -t ${ECR_REPO}:${IMAGE_TAG} .
                    docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REPO}:latest
                """
            }
        }
        
        stage('Generate SBOM') {
            steps {
                echo 'Generating SBOM with Syft...'
                sh """
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        anchore/syft:latest ${ECR_REPO}:${IMAGE_TAG} \
                        -o cyclonedx-json > sbom-cyclonedx.json
                    
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        anchore/syft:latest ${ECR_REPO}:${IMAGE_TAG} \
                        -o spdx-json > sbom-spdx.json
                """
                archiveArtifacts artifacts: 'sbom-*.json', fingerprint: true
            }
        }
        
        stage('Container Image Scan') {
            steps {
                echo 'Scanning container image with Trivy...'
                script {
                    sh """
                        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            aquasec/trivy:latest image \
                            --format json \
                            --output trivy-report.json \
                            ${ECR_REPO}:${IMAGE_TAG}
                        
                        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            aquasec/trivy:latest image \
                            --severity HIGH,CRITICAL \
                            --exit-code 1 \
                            ${ECR_REPO}:${IMAGE_TAG} || TRIVY_EXIT=\$?
                    """
                    
                    def trivyReport = readJSON file: 'trivy-report.json'
                    def criticalCount = 0
                    def highCount = 0
                    
                    trivyReport.Results?.each { result ->
                        result.Vulnerabilities?.each { vuln ->
                            if (vuln.Severity == 'CRITICAL') criticalCount++
                            if (vuln.Severity == 'HIGH') highCount++
                        }
                    }
                    
                    if (criticalCount > 0 || highCount > 0) {
                        env.QUALITY_GATE_FAILED = 'true'
                        error("❌ CRITICAL: Found ${criticalCount} Critical and ${highCount} High vulnerabilities")
                    }
                    echo '✅ Container scan passed'
                }
            }
        }
        
        stage('Quality Gate Check') {
            steps {
                script {
                    if (env.QUALITY_GATE_FAILED == 'true') {
                        error('❌ DEPLOYMENT BLOCKED: Quality gate failed due to security findings')
                    }
                    echo '✅ All quality gates passed - proceeding to deployment'
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                echo 'Pushing image to Amazon ECR...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                        docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:latest
                        
                        docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
                    """
                }
            }
        }
        
        stage('Update ECS Task Definition') {
            steps {
                echo 'Registering new ECS task definition...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    script {
                        sh """
                            aws ecs describe-task-definition \
                                --task-definition ${ECS_TASK_FAMILY} \
                                --query 'taskDefinition' > current-task-def.json
                            
                            jq --arg IMAGE "${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}" \
                                '.containerDefinitions[0].image = \$IMAGE | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
                                current-task-def.json > new-task-def.json
                            
                            NEW_REVISION=\$(aws ecs register-task-definition \
                                --cli-input-json file://new-task-def.json \
                                --query 'taskDefinition.revision' \
                                --output text)
                            
                            echo "Registered new task definition revision: \$NEW_REVISION"
                            echo "NEW_REVISION=\$NEW_REVISION" >> task-revision.env
                        """
                    }
                }
            }
        }
        
        stage('Deploy to ECS') {
            steps {
                echo 'Updating ECS service with new task definition...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    script {
                        sh """
                            source task-revision.env
                            
                            aws ecs update-service \
                                --cluster ${ECS_CLUSTER} \
                                --service ${ECS_SERVICE} \
                                --task-definition ${ECS_TASK_FAMILY}:\$NEW_REVISION \
                                --force-new-deployment
                            
                            echo "Waiting for deployment to complete..."
                            aws ecs wait services-stable \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE}
                            
                            echo "✅ ECS service updated successfully"
                        """
                    }
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                echo 'Verifying deployment health...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    script {
                        sh """
                            # Get service status
                            SERVICE_STATUS=\$(aws ecs describe-services \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE} \
                                --query 'services[0].status' \
                                --output text)
                            
                            RUNNING_COUNT=\$(aws ecs describe-services \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE} \
                                --query 'services[0].runningCount' \
                                --output text)
                            
                            DESIRED_COUNT=\$(aws ecs describe-services \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE} \
                                --query 'services[0].desiredCount' \
                                --output text)
                            
                            echo "Service Status: \$SERVICE_STATUS"
                            echo "Running Tasks: \$RUNNING_COUNT/\$DESIRED_COUNT"
                            
                            if [ "\$SERVICE_STATUS" = "ACTIVE" ] && [ "\$RUNNING_COUNT" = "\$DESIRED_COUNT" ]; then
                                echo "✅ Deployment verification successful"
                            else
                                echo "❌ Deployment verification failed"
                                exit 1
                            fi
                        """
                    }
                }
            }
        }
        
        stage('Cleanup Old Images') {
            steps {
                echo 'Cleaning up old ECR images...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    script {
                        sh """
                            # Keep only last 10 images
                            OLD_IMAGES=\$(aws ecr list-images \
                                --repository-name ${ECR_REPO} \
                                --filter tagStatus=TAGGED \
                                --query 'imageIds[10:]' \
                                --output json)
                            
                            if [ "\$OLD_IMAGES" != "[]" ] && [ "\$OLD_IMAGES" != "null" ]; then
                                echo "Deleting old images..."
                                aws ecr batch-delete-image \
                                    --repository-name ${ECR_REPO} \
                                    --image-ids "\$OLD_IMAGES"
                                echo "✅ Old images cleaned up"
                            else
                                echo "No old images to clean up"
                            fi
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo 'Archiving security reports and artifacts...'
            archiveArtifacts artifacts: '**/*-report.json, **/*-report.xml, sbom-*.json', 
                            fingerprint: true, 
                            allowEmptyArchive: true
            
            publishHTML([
                allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: '.',
                reportFiles: 'trivy-report.json',
                reportName: 'Trivy Security Report'
            ])
            
            // Clean up workspace
            sh 'docker system prune -f || true'
            cleanWs()
        }
        
        success {
            echo '🎉 Pipeline completed successfully!'
            script {
                def message = """
                ✅ **Deployment Successful**
                
                **Build:** ${BUILD_NUMBER}
                **Image:** ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                **ECS Service:** ${ECS_SERVICE}
                **Security Scans:** All passed
                
                **Artifacts Generated:**
                - SBOM (CycloneDX & SPDX)
                - Security scan reports
                - Container vulnerability report
                """
                echo message
            }
        }
        
        failure {
            echo '❌ Pipeline failed!'
            script {
                if (env.QUALITY_GATE_FAILED == 'true') {
                    echo '🚫 **SECURITY GATE FAILURE** - Deployment blocked due to security findings'
                } else {
                    echo '💥 **BUILD FAILURE** - Check logs for technical issues'
                }
            }
        }
    }
}tributes, .compatibilities, .registeredAt, .registeredBy)' \
                                current-task-def.json > new-task-def.json
                            
                            aws ecs register-task-definition \
                                --cli-input-json file://new-task-def.json \
                                --query 'taskDefinition.revision' \
                                --output text > task-revision.txt
                            
                            echo "New task definition revision: \$(cat task-revision.txt)"
                        """
                    }
                }
            }
        }
        
        stage('Deploy to ECS') {
            steps {
                echo 'Updating ECS service...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    script {
                        sh """
                            TASK_REVISION=\$(cat task-revision.txt)
                            
                            aws ecs update-service \
                                --cluster ${ECS_CLUSTER} \
                                --service ${ECS_SERVICE} \
                                --task-definition ${ECS_TASK_FAMILY}:\${TASK_REVISION} \
                                --force-new-deployment
                            
                            echo "Waiting for service to stabilize..."
                            aws ecs wait services-stable \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE}
                        """
                        echo '✅ ECS service updated successfully'
                    }
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                echo 'Verifying deployment health...'
                withAWS(credentials: 'aws-credentials', region: env.AWS_REGION) {
                    script {
                        sh """
                            RUNNING_COUNT=\$(aws ecs describe-services \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE} \
                                --query 'services[0].runningCount' \
                                --output text)
                            
                            echo "Running tasks: \${RUNNING_COUNT}"
                            
                            if [ "\${RUNNING_COUNT}" -lt "1" ]; then
                                echo "❌ No running tasks found"
                                exit 1
                            fi
                            
                            TASK_ARN=\$(aws ecs list-tasks \
                                --cluster ${ECS_CLUSTER} \
                                --service-name ${ECS_SERVICE} \
                                --query 'taskArns[0]' \
                                --output text)
                            
                            echo "✅ Deployment verified - Task: \${TASK_ARN}"
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: '*-report.json', allowEmptyArchive: true, fingerprint: true
            sh """
                docker rmi ${ECR_REPO}:${IMAGE_TAG} || true
                docker rmi ${ECR_REPO}:latest || true
                docker rmi ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG} || true
                docker rmi ${ECR_REGISTRY}/${ECR_REPO}:latest || true
            """
        }
        success {
            echo '✅ Pipeline completed successfully! Application deployed to ECS.'
        }
        failure {
            echo '❌ Pipeline failed! Check security reports and logs.'
        }
    }
}
