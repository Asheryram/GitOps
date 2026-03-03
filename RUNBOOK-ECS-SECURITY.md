# Jenkins CI/CD Pipeline with ECS & Security Scanning — Runbook

> **Stack:** Node.js · Jenkins · AWS ECS/ECR · Security Scanning (Gitleaks, SonarQube, Snyk, Trivy) · Slack Notifications

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [AWS Infrastructure Setup](#3-aws-infrastructure-setup)
4. [Jenkins Server Setup](#4-jenkins-server-setup)
5. [Security Tools Configuration](#5-security-tools-configuration)
6. [Jenkins Credentials Setup](#6-jenkins-credentials-setup)
7. [Create Pipeline Job](#7-create-pipeline-job)
8. [Pipeline Stages Explained](#8-pipeline-stages-explained)
9. [Deployment Procedures](#9-deployment-procedures)
10. [Monitoring & Verification](#10-monitoring--verification)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Architecture Overview

```
Developer → GitHub → Jenkins (EC2)
                        │
                   Pipeline Stages:
                   1. Configure (SSM)
                   2. Checkout
                   3. Secret Scan (Gitleaks)
                   4. Install Dependencies
                   5. SAST (SonarQube)
                   6. SCA (npm audit + Snyk)
                   7. Unit Tests
                   8. Docker Build
                   9. SBOM (Syft)
                   10. Container Scan (Trivy)
                   11. Push to ECR
                   12. Update ECS Task
                   13. Deploy to ECS
                   14. Verify Deployment
                   15. Cleanup Old Images
                        │
                   AWS ECS Cluster
                        │
                   Running Containers
```

**Failure Routing:**
- Critical app issues (secrets, CVEs) → `#app-alerts`
- Pipeline/infra issues → `#devops-alerts`
- Success → both channels

---

## 2. Prerequisites

### Local Machine
- AWS CLI configured (`aws configure`)
- Terraform installed
- Git configured
- Docker Hub account
- Snyk account (free tier)
- SonarQube Cloud account (or self-hosted)
- Slack workspace with webhook

### AWS Requirements
- IAM user/role with permissions:
  - EC2, VPC, Security Groups
  - ECR (create repo, push/pull images)
  - ECS (create cluster, service, task definitions)
  - SSM Parameter Store (read/write)
  - IAM (create roles for ECS tasks)

---

## 3. AWS Infrastructure Setup

### 3.1 Create ECR Repository

```bash
aws ecr create-repository --repository-name my-app --region us-east-1
```

### 3.2 Create ECS Cluster

```bash
aws ecs create-cluster --cluster-name my-app-cluster --region us-east-1
```

### 3.3 Create ECS Task Definition

Create `task-definition.json`:

```json
{
  "family": "my-app-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "my-app",
      "image": "ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/my-app:latest",
      "portMappings": [{"containerPort": 5000, "protocol": "tcp"}],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/my-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ],
  "executionRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::ACCOUNT_ID:role/ecsTaskRole"
}
```

Register it:

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

### 3.4 Create ECS Service

```bash
aws ecs create-service \
  --cluster my-app-cluster \
  --service-name my-app-service \
  --task-definition my-app-task \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

### 3.5 Store Configuration in SSM Parameter Store

```bash
aws ssm put-parameter --name /jenkins/cicd/aws-region --value us-east-1 --type String
aws ssm put-parameter --name /jenkins/cicd/ecr-repo --value my-app --type String
aws ssm put-parameter --name /jenkins/cicd/ecs-cluster --value my-app-cluster --type String
aws ssm put-parameter --name /jenkins/cicd/ecs-service --value my-app-service --type String
aws ssm put-parameter --name /jenkins/cicd/ecs-task-family --value my-app-task --type String
aws ssm put-parameter --name /jenkins/cicd/sonar-project --value my-app --type String
aws ssm put-parameter --name /jenkins/cicd/sonar-org --value my-org --type String
aws ssm put-parameter --name /jenkins/cicd/images-to-keep --value 5 --type String
```

### 3.6 IAM Role for Jenkins

Create role with policies:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParametersByPath",
        "sts:GetCallerIdentity",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:ListImages",
        "ecr:BatchDeleteImage",
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

Attach to Jenkins EC2 instance profile.

---

## 4. Jenkins Server Setup

### 4.1 Launch EC2 Instance

```bash
# Amazon Linux 2
# t3.medium (2 vCPU, 4GB RAM minimum)
# Attach IAM role from 3.6
# Security group: allow 8080 from your IP
```

### 4.2 Install Jenkins

```bash
ssh -i keypair.pem ec2-user@<JENKINS_IP>

# Install Docker
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Install Jenkins
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo yum install -y java-11-amazon-corretto jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Install additional tools
sudo yum install -y jq git

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install sonar-scanner
wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip
unzip sonar-scanner-cli-5.0.1.3006-linux.zip
sudo mv sonar-scanner-5.0.1.3006-linux /opt/sonar-scanner
sudo ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner
```

### 4.3 Get Initial Admin Password

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### 4.4 Install Jenkins Plugins

Navigate to **Manage Jenkins → Plugins → Available**:

- Pipeline
- Git
- Credentials Binding
- Docker Pipeline
- NodeJS
- SonarQube Scanner
- Slack Notification
- Pipeline Utility Steps

**Restart Jenkins after installation.**

### 4.5 Configure Tools

**Manage Jenkins → Tools:**

**NodeJS:**
- Name: `nodejs-20`
- Version: `NodeJS 20.x`
- Install automatically: ✅

**SonarQube Scanner:**
- Name: `SonarQube`
- Install automatically: ✅
- Version: Latest

---

## 5. Security Tools Configuration

### 5.1 SonarQube Cloud Setup

1. Go to https://sonarcloud.io
2. Create organization
3. Create project → get project key
4. Generate token: **My Account → Security → Generate Token**
5. Save token for Jenkins credentials

### 5.2 Snyk Setup

1. Go to https://snyk.io
2. Sign up (free tier)
3. Generate token: **Account Settings → API Token**
4. Save token for Jenkins credentials

### 5.3 Slack Webhook Setup

1. Go to https://api.slack.com/apps
2. Create New App → From scratch
3. Add features: **Incoming Webhooks**
4. Activate webhooks
5. Add webhook to workspace
6. Select channels: `#app-alerts` and `#devops-alerts`
7. Copy webhook URLs

---

## 6. Jenkins Credentials Setup

**Manage Jenkins → Credentials → System → Global → Add Credentials**

### 6.1 SonarQube Token

- Kind: `Secret text`
- Secret: `<your-sonarqube-token>`
- ID: `sonarqube-token`

**Then configure SonarQube server:**

**Manage Jenkins → System → SonarQube servers:**
- Name: `SonarQube`
- Server URL: `https://sonarcloud.io`
- Server authentication token: Select `sonarqube-token`

### 6.2 Snyk Token

- Kind: `Secret text`
- Secret: `<your-snyk-token>`
- ID: `snyk-token`

### 6.3 Slack Credentials

- Kind: `Secret text`
- Secret: `<slack-webhook-url>`
- ID: `slack-webhook`

**Then configure Slack:**

**Manage Jenkins → System → Slack:**
- Workspace: `<your-workspace>`
- Credential: Select `slack-webhook`
- Default channel: `#devops-alerts`
- Test connection

---

## 7. Create Pipeline Job

### 7.1 Update Jenkinsfile

Ensure `Jenkinsfile` is in your repository root.

### 7.2 Create Job

1. **Dashboard → New Item**
2. Name: `ecs-security-pipeline`
3. Type: **Pipeline**
4. **OK**

**Configuration:**

**General:**
- ✅ Discard old builds → Max: `10`

**Build Triggers:**
- ✅ GitHub hook trigger for GITScm polling

**Pipeline:**
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: `https://github.com/YOUR_USERNAME/YOUR_REPO.git`
- Credentials: (add GitHub token if private)
- Branch: `*/main`
- Script Path: `Jenkinsfile`

**Save**

---

## 8. Pipeline Stages Explained

### Stage 1: Configure Environment
- Pulls all config from SSM Parameter Store (`/jenkins/cicd/`)
- Sets environment variables
- Captures Git commit metadata

### Stage 2: Checkout
- Clones repository from GitHub

### Stage 3: Secret Scanning (Gitleaks)
- Scans for hardcoded secrets, API keys, passwords
- **CRITICAL:** Any secret found = pipeline FAILS

### Stage 4: Install Dependencies
- Runs `npm ci` for reproducible builds

### Stage 5: SAST - SonarQube
- Static code analysis
- Quality gate check
- **CRITICAL:** ERROR status = pipeline FAILS
- **UNSTABLE:** WARN status = pipeline continues but marked unstable

### Stage 6: SCA - Dependency Check
- `npm audit` for known vulnerabilities
- `Snyk` for deeper CVE analysis
- **CRITICAL:** CRITICAL severity CVEs = pipeline FAILS
- **UNSTABLE:** HIGH/MEDIUM = pipeline continues but marked unstable

### Stage 7: Unit Tests
- Runs `npm test`
- Any test failure = pipeline FAILS

### Stage 8: Build Docker Image
- Builds image with build number tag
- Tags as `:latest` and `:BUILD_NUMBER`

### Stage 9: Generate SBOM
- Creates Software Bill of Materials with Syft
- Generates CycloneDX and SPDX formats
- Archives for compliance

### Stage 10: Container Image Scan (Trivy)
- Scans Docker image for OS and library vulnerabilities
- **CRITICAL:** CRITICAL CVEs = pipeline FAILS
- **UNSTABLE:** HIGH/MEDIUM = pipeline continues

### Stage 11: Push to ECR
- Authenticates to AWS ECR
- Pushes both tags to registry

### Stage 12: Update ECS Task Definition
- Fetches current task definition
- Updates container image to new build
- Registers new revision

### Stage 13: Deploy to ECS
- Updates ECS service with new task definition
- Waits for service to stabilize

### Stage 14: Verify Deployment
- Checks service status = ACTIVE
- Verifies running count = desired count

### Stage 15: Cleanup Old Images
- Keeps only N most recent images in ECR (default: 5)
- Deletes older images to save costs

---

## 9. Deployment Procedures

### 9.1 Standard Deployment

```bash
# 1. Make changes
vim app.js

# 2. Test locally
npm test

# 3. Commit and push
git add .
git commit -m "feat: new feature"
git push origin main

# 4. Jenkins auto-triggers (if webhook configured)
# Or manually: Jenkins → ecs-security-pipeline → Build Now
```

### 9.2 Manual ECS Deployment (Emergency)

```bash
# Update service to specific image
aws ecs update-service \
  --cluster my-app-cluster \
  --service my-app-service \
  --force-new-deployment

# Or rollback to specific build
aws ecs update-service \
  --cluster my-app-cluster \
  --service my-app-service \
  --task-definition my-app-task:REVISION_NUMBER
```

### 9.3 Rollback Procedure

```bash
# 1. Find previous working revision
aws ecs list-task-definitions --family-prefix my-app-task

# 2. Update service
aws ecs update-service \
  --cluster my-app-cluster \
  --service my-app-service \
  --task-definition my-app-task:PREVIOUS_REVISION

# 3. Wait for stabilization
aws ecs wait services-stable \
  --cluster my-app-cluster \
  --services my-app-service
```

---

## 10. Monitoring & Verification

### 10.1 Check ECS Service

```bash
aws ecs describe-services \
  --cluster my-app-cluster \
  --services my-app-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

### 10.2 View Container Logs

```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster my-app-cluster \
  --service-name my-app-service \
  --query 'taskArns[0]' \
  --output text)

# View logs (if using CloudWatch)
aws logs tail /ecs/my-app --follow
```

### 10.3 Check Application Health

```bash
# Get ALB DNS or task public IP
curl http://<ALB_DNS>/health
```

### 10.4 Review Security Reports

All reports archived in Jenkins:
- `gitleaks-report.json`
- `npm-audit-report.json`
- `snyk-report.json`
- `trivy-report.json`
- `sbom-cyclonedx.json`
- `sbom-spdx.json`

Access: **Build → Artifacts**

---

## 11. Troubleshooting

### 11.1 SSM Parameters Not Found

**Error:** `No SSM parameters found at /jenkins/cicd/`

**Fix:**
```bash
# Verify parameters exist
aws ssm get-parameters-by-path --path /jenkins/cicd/

# Check IAM role attached to Jenkins EC2
aws sts get-caller-identity

# Ensure role has ssm:GetParametersByPath permission
```

### 11.2 SonarQube Quality Gate Timeout

**Error:** `SonarQube scanner error: timeout`

**Fix:**
```groovy
// In Jenkinsfile, increase timeout
timeout(time: 10, unit: 'MINUTES') {
    def qg = waitForQualityGate()
}
```

Or skip quality gate wait:
```groovy
// Add to sonar-scanner command
-Dsonar.qualitygate.wait=false
```

### 11.3 Snyk Authentication Failed

**Error:** `Snyk test failed: Unauthorized`

**Fix:**
- Verify credential ID is exactly `snyk-token`
- Regenerate token at snyk.io
- Update credential in Jenkins

### 11.4 ECR Push Failed

**Error:** `denied: Your authorization token has expired`

**Fix:**
```bash
# Verify IAM role has ECR permissions
aws ecr get-login-password --region us-east-1

# Check ECR repository exists
aws ecr describe-repositories --repository-names my-app
```

### 11.5 ECS Service Won't Stabilize

**Error:** `Deployment verification failed`

**Fix:**
```bash
# Check service events
aws ecs describe-services \
  --cluster my-app-cluster \
  --services my-app-service \
  --query 'services[0].events[0:5]'

# Check task stopped reason
aws ecs describe-tasks \
  --cluster my-app-cluster \
  --tasks <TASK_ARN> \
  --query 'tasks[0].stoppedReason'

# Common issues:
# - Container health check failing
# - Insufficient CPU/memory
# - Security group blocking traffic
# - Task role missing permissions
```

### 11.6 Docker Socket Permission Denied

**Error:** `permission denied while trying to connect to Docker daemon`

**Fix:**
```bash
# Add jenkins user to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### 11.7 Gitleaks False Positives

**Fix:** Create `.gitleaksignore` in repo root:
```
# Ignore test files
test/**
*.test.js

# Ignore specific findings
<commit-sha>:<rule-id>:<file>:<line>
```

### 11.8 Slack Notifications Not Sending

**Fix:**
- Verify webhook URL is correct
- Test webhook manually:
```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test message"}' \
  <WEBHOOK_URL>
```
- Check Jenkins System Log for errors

### 11.9 High Memory Usage on Jenkins

**Fix:**
```bash
# Increase Jenkins heap size
sudo vim /etc/sysconfig/jenkins
# Add: JENKINS_JAVA_OPTIONS="-Xmx2g -Xms1g"

sudo systemctl restart jenkins
```

### 11.10 Pipeline Slow Performance

**Optimizations:**

1. **Skip SonarQube quality gate wait:**
```groovy
-Dsonar.qualitygate.wait=false
```

2. **Add exclusions:**
```groovy
-Dsonar.exclusions=**/node_modules/**,**/dist/**,**/build/**
```

3. **Use Docker layer caching:**
```dockerfile
# In Dockerfile, order layers by change frequency
COPY package*.json ./
RUN npm ci
COPY . .
```

4. **Parallel stages:**
```groovy
parallel {
    stage('npm audit') { steps { runNpmAudit() } }
    stage('Snyk') { steps { runSnykScan() } }
}
```

---

## Quick Reference

### Essential Commands

```bash
# View Jenkins logs
sudo journalctl -u jenkins -f

# Restart Jenkins
sudo systemctl restart jenkins

# Check Docker on Jenkins
docker ps
docker images

# AWS ECS quick status
aws ecs describe-services --cluster my-app-cluster --services my-app-service

# Force new deployment
aws ecs update-service --cluster my-app-cluster --service my-app-service --force-new-deployment

# View ECR images
aws ecr list-images --repository-name my-app

# Delete old ECR images
aws ecr batch-delete-image --repository-name my-app --image-ids imageTag=old-tag
```

### Pipeline Environment Variables

Set in SSM Parameter Store (`/jenkins/cicd/`):
- `aws-region`
- `ecr-repo`
- `ecs-cluster`
- `ecs-service`
- `ecs-task-family`
- `sonar-project`
- `sonar-org`
- `images-to-keep`

### Security Scan Thresholds

| Tool | Critical → FAIL | High/Medium → UNSTABLE |
|------|----------------|------------------------|
| Gitleaks | Any secret | N/A |
| SonarQube | ERROR status | WARN status |
| npm audit | CRITICAL CVEs | HIGH/MEDIUM CVEs |
| Snyk | CRITICAL CVEs | HIGH/MEDIUM CVEs |
| Trivy | CRITICAL CVEs | HIGH/MEDIUM CVEs |

---

**Last Updated:** 2024
**Pipeline Version:** 2.0
