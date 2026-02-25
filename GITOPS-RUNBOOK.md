# GitOps RunBook - Secure CI/CD Pipeline with ECS/EC2 Deployment

> **Enhanced CI/CD Pipeline with Security Scanning and Flexible Deployment**
>
> **Stack:** Node.js app · Jenkins · Amazon ECR · Amazon ECS/EC2 · Security Scanning (SAST/SCA/Container/Secrets) · SBOM Generation · Terraform

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites and Setup](#2-prerequisites-and-setup)
3. [Infrastructure Deployment](#3-infrastructure-deployment)
4. [Security Tools Configuration](#4-security-tools-configuration)
5. [Jenkins Pipeline Configuration](#5-jenkins-pipeline-configuration)
6. [Deployment Options](#6-deployment-options)
7. [Security Scanning Procedures](#7-security-scanning-procedures)
8. [Deployment Workflows](#8-deployment-workflows)
9. [Monitoring and Logging](#9-monitoring-and-logging)
10. [Troubleshooting](#10-troubleshooting)
11. [Security Testing](#11-security-testing)
12. [Cleanup and Maintenance](#12-cleanup-and-maintenance)

---

## 1. Architecture Overview

### Current Implementation: Dual Deployment Support

```
Developer → GitHub → Jenkins Pipeline → Security Scans → ECR → ECS Fargate OR EC2
                           │
                    Security Gates:
                    ├── Secret Scan (Gitleaks)
                    ├── SAST (SonarQube)
                    ├── SCA (npm audit/Snyk)
                    ├── Container Scan (Trivy)
                    ├── SBOM Generation (Syft)
                    └── Quality Gate Check
                           │
                    ✅ Pass → Deploy to Target
                    ❌ Fail → Block Pipeline
```

**Infrastructure Options:**
- **Option A - ECS Deployment**: Uses `Jenkinsfile.ecs` for containerized deployment to ECS Fargate
- **Option B - EC2 Deployment**: Uses Terraform-managed EC2 instances for direct deployment

**AWS Resources:**
- **Terraform Managed**: VPC, EC2 instances, Security Groups, Key Pairs
- **Manual/Pipeline Managed**: ECR Repository, ECS Cluster, ECS Service, CloudWatch Logs

---

## 2. Prerequisites and Setup

### 2.1 Required Tools

```bash
# Install required tools
aws --version          # AWS CLI v2
docker --version       # Docker Engine
terraform --version    # Terraform >= 1.0
node --version         # Node.js 20+
npm --version          # npm package manager
```

### 2.2 AWS Account Setup

```bash
# Configure AWS CLI
aws configure
# Enter: Access Key, Secret Key, Region (us-east-1), Output (json)

# Verify access
aws sts get-caller-identity
aws ecr describe-repositories || echo "No ECR repos yet"
```

### 2.3 Required AWS Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*",
        "ecs:*",
        "iam:PassRole",
        "logs:*",
        "cloudwatch:*",
        "elasticloadbalancing:*",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 3. Infrastructure Deployment

### 3.1 Terraform Infrastructure Setup

```bash
# Navigate to terraform directory
cd terraform/

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# aws_region = "us-east-1"
# project_name = "cicd-pipeline"
# environment = "dev"
# allowed_ips = ["YOUR_IP/32"]  # Replace with your IP
# jenkins_admin_password = "your-secure-password"
```

### 3.2 Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Note the outputs:
# - Jenkins server public IP
# - Application server public IP
# - VPC and subnet IDs
```

### 3.3 Add ECR Module (if needed)

```bash
# Add ECR module to main.tf
echo '
# ECR Module
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}' >> main.tf

# Apply ECR changes
terraform plan -target=module.ecr
terraform apply -target=module.ecr
```

### 3.4 Verify Infrastructure

```bash
# Get infrastructure outputs
terraform output

# Test Jenkins access
JENKINS_IP=$(terraform output -raw jenkins_public_ip)
curl -f http://$JENKINS_IP:8080 || echo "Jenkins starting up..."

# Get ECR repository URL (if ECR module added)
ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "ECR not deployed")
echo "ECR Repository: $ECR_REPO"
```

---

## 4. Security Tools Configuration

### 4.1 SonarQube Setup

```bash
# Run SonarQube in Docker
docker run -d --name sonarqube \
    -p 9000:9000 \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    sonarqube:latest

# Wait for startup (2-3 minutes)
curl -u admin:admin http://localhost:9000/api/system/status

# Create project token
curl -u admin:admin -X POST \
    "http://localhost:9000/api/user_tokens/generate?name=jenkins&type=PROJECT_ANALYSIS_TOKEN"
```

### 4.2 Snyk Setup

```bash
# Install Snyk CLI
npm install -g snyk

# Authenticate (get token from snyk.io)
snyk auth <your-snyk-token>

# Test project
snyk test --severity-threshold=high
```

### 4.3 Security Tool Verification

```bash
# Test Gitleaks
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect --source /repo --no-git

# Test Trivy
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image node:20-alpine

# Test Syft
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/syft:latest node:20-alpine -o cyclonedx-json
```

---

## 5. Jenkins Pipeline Configuration

### 5.1 Access Jenkins Server

```bash
# Get Jenkins IP from Terraform output
JENKINS_IP=$(terraform output -raw jenkins_public_ip)
echo "Jenkins URL: http://$JENKINS_IP:8080"

# Get initial admin password (if needed)
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$JENKINS_IP \
    "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
```

### 5.2 Required Jenkins Credentials

Navigate to **Manage Jenkins → Credentials → Global**:

| Credential ID | Type | Description |
|---------------|------|-------------|
| `aws-account-id` | Secret text | AWS Account ID (12 digits) |
| `aws-credentials` | AWS Credentials | AWS Access Key + Secret |
| `snyk-token` | Secret text | Snyk authentication token |
| `sonarqube-token` | Secret text | SonarQube project token |
| `ecr-repo-uri` | Secret text | ECR repository URI from Terraform |

### 5.3 Get ECR Repository URI

```bash
# If ECR module is deployed
ECR_REPO_URI=$(terraform output -raw ecr_repository_url 2>/dev/null)

# If ECR not in Terraform, create manually
if [ -z "$ECR_REPO_URI" ]; then
    aws ecr create-repository --repository-name cicd-node-app --region us-east-1
    ECR_REPO_URI=$(aws ecr describe-repositories --repository-names cicd-node-app --query 'repositories[0].repositoryUri' --output text)
fi

echo "ECR Repository URI: $ECR_REPO_URI"
```

### 5.2 Jenkins Plugins Required

```bash
# Install via Manage Jenkins → Plugins
- Pipeline
- AWS Steps
- Docker Pipeline
- SonarQube Scanner
- Blue Ocean (optional)
- CloudWatch Logs (optional)
```

### 5.3 SonarQube Integration

**Manage Jenkins → Configure System → SonarQube servers:**
- Name: `SonarQube`
- Server URL: `http://localhost:9000`
- Server authentication token: `sonarqube-token`

### 5.4 Pipeline Job Creation

```bash
# Create new Pipeline job
1. New Item → Pipeline
2. Name: "secure-cicd-pipeline"
3. Pipeline script from SCM
4. Repository: your-github-repo
5. Script Path: Jenkinsfile.ecs
```

---

## 6. ECS Service Deployment

### 6.1 Deploy Application to EC2 (Current Setup)

```bash
# Get application server IP
APP_SERVER_IP=$(terraform output -raw app_server_public_ip)
echo "Application Server: http://$APP_SERVER_IP:3000"

# SSH to application server
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP

# Check application status
curl -f http://$APP_SERVER_IP:3000/health || echo "Application not running"
```

### 6.2 Optional: Add ECS Support

To deploy to ECS instead of EC2, add ECS modules to Terraform:

```bash
# Create ECS module structure
mkdir -p terraform/modules/ecs

# Add ECS cluster, service, and task definition modules
# (This would require additional Terraform configuration)
```

### 6.3 Application Deployment Verification

```bash
# Test application endpoints
APP_URL="http://$(terraform output -raw app_server_public_ip):3000"

# Health check
curl -f $APP_URL/health

# Application response
curl -f $APP_URL/

# Check application logs
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$(terraform output -raw app_server_public_ip) \
    "sudo journalctl -u node-app -f"
```

---

## 7. Security Scanning Procedures

### 7.1 Secret Scanning with Gitleaks

```bash
# Manual secret scan
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
    --source /repo \
    --report-path gitleaks-report.json \
    --report-format json \
    --no-git

# Check results
if [ -s gitleaks-report.json ]; then
    echo "❌ Secrets detected!"
    cat gitleaks-report.json
else
    echo "✅ No secrets found"
fi
```

### 7.2 SAST with SonarQube

```bash
# Run SonarQube scan
sonar-scanner \
    -Dsonar.projectKey=cicd-node-app \
    -Dsonar.sources=. \
    -Dsonar.host.url=http://localhost:9000 \
    -Dsonar.login=<sonar-token>

# Check quality gate
curl -u <token>: \
    "http://localhost:9000/api/qualitygates/project_status?projectKey=cicd-node-app"
```

### 7.3 SCA with npm audit and Snyk

```bash
# npm audit
npm audit --audit-level=high

# Snyk vulnerability scan
snyk test --severity-threshold=high --json > snyk-report.json

# Check results
if [ $? -ne 0 ]; then
    echo "❌ High/Critical vulnerabilities found!"
    snyk test --severity-threshold=high
else
    echo "✅ No high/critical vulnerabilities"
fi
```

### 7.4 Container Scanning with Trivy

```bash
# Scan container image
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image \
    --format json \
    --output trivy-report.json \
    $ECR_REGISTRY/cicd-node-app:$BUILD_NUMBER

# Check for HIGH/CRITICAL vulnerabilities
trivy image --severity HIGH,CRITICAL --exit-code 1 \
    $ECR_REGISTRY/cicd-node-app:$BUILD_NUMBER
```

### 7.5 SBOM Generation with Syft

```bash
# Generate SBOM
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/syft:latest \
    $ECR_REGISTRY/cicd-node-app:$BUILD_NUMBER \
    -o cyclonedx-json > sbom.json

# Verify SBOM
echo "✅ SBOM generated with $(jq '.components | length' sbom.json) components"
```

---

## 8. Deployment Workflows

### 8.1 Manual Deployment Process

```bash
# 1. Build and push image to ECR (if using ECR)
ECR_REPO_URI=$(terraform output -raw ecr_repository_url 2>/dev/null)
if [ ! -z "$ECR_REPO_URI" ]; then
    docker build -t cicd-node-app:latest .
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO_URI
    docker tag cicd-node-app:latest $ECR_REPO_URI:latest
    docker push $ECR_REPO_URI:latest
fi

# 2. Deploy to application server
APP_SERVER_IP=$(terraform output -raw app_server_public_ip)
scp -i ~/.ssh/$(terraform output -raw key_name).pem -r . ec2-user@$APP_SERVER_IP:/tmp/app/
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP \
    "cd /tmp/app && npm install && sudo systemctl restart node-app"

# 3. Verify deployment
curl -f http://$APP_SERVER_IP:3000/health
```

### 8.2 Pipeline Deployment Flow

```mermaid
graph TD
    A[Code Push] --> B[Jenkins Trigger]
    B --> C[Secret Scan]
    C --> D{Secrets Found?}
    D -->|Yes| E[❌ Block Pipeline]
    D -->|No| F[SAST Scan]
    F --> G[SCA Scan]
    G --> H[Build Image]
    H --> I[Container Scan]
    I --> J{Vulnerabilities?}
    J -->|High/Critical| K[❌ Block Pipeline]
    J -->|Low/None| L[Generate SBOM]
    L --> M[Push to ECR/Deploy to EC2]
    M --> N[Health Check]
    N --> O[✅ Deployment Complete]
```

### 8.3 Rollback Procedure

```bash
# For EC2 deployment - rollback to previous version
APP_SERVER_IP=$(terraform output -raw app_server_public_ip)

# SSH to server and rollback
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP << 'EOF'
    # Stop current application
    sudo systemctl stop node-app
    
    # Restore from backup (if backup exists)
    if [ -d /opt/app-backup ]; then
        sudo cp -r /opt/app-backup/* /opt/app/
        sudo systemctl start node-app
        echo "Rollback completed"
    else
        echo "No backup found"
    fi
EOF

# Verify rollback
curl -f http://$APP_SERVER_IP:3000/health
```

---

## 9. Monitoring and Logging

### 9.1 Application Logs Access

```bash
# Access application server logs
APP_SERVER_IP=$(terraform output -raw app_server_public_ip)

# View application logs
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP \
    "sudo journalctl -u node-app -f"

# View system logs
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP \
    "sudo tail -f /var/log/messages"

# Search for errors
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP \
    "sudo journalctl -u node-app --since '1 hour ago' | grep ERROR"
```

### 9.2 Jenkins Logs Access

```bash
# Access Jenkins server logs
JENKINS_IP=$(terraform output -raw jenkins_public_ip)

# View Jenkins logs
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$JENKINS_IP \
    "sudo tail -f /var/log/jenkins/jenkins.log"

# View build logs via Jenkins UI
echo "Jenkins URL: http://$JENKINS_IP:8080"
```

### 9.3 Application Health Monitoring

```bash
# Get application server IP
APP_SERVER_IP=$(terraform output -raw app_server_public_ip)
APP_URL="http://$APP_SERVER_IP:3000"

# Health check
curl -f $APP_URL/health || echo "❌ Health check failed"

# Performance check
curl -w "@curl-format.txt" -o /dev/null -s $APP_URL/

# Create curl format file for timing
cat > curl-format.txt << 'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF
```

---

## 10. Troubleshooting

### 10.1 Common Pipeline Issues

**Issue: Secret scan fails**
```bash
# Debug gitleaks
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect --source /repo --verbose

# Check .gitleaksignore file
cat .gitleaksignore
```

**Issue: SonarQube quality gate fails**
```bash
# Check quality gate status
curl -u $SONAR_TOKEN: "http://localhost:9000/api/qualitygates/project_status?projectKey=cicd-node-app"

# View detailed issues
curl -u $SONAR_TOKEN: "http://localhost:9000/api/issues/search?componentKeys=cicd-node-app&severities=BLOCKER,CRITICAL"
```

**Issue: Container scan fails**
```bash
# Debug Trivy scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image --debug $IMAGE_NAME

# Check specific vulnerabilities
trivy image --format table $IMAGE_NAME
```

### 10.2 ECS Deployment Issues

**Issue: Service fails to start**
```bash
# Check service events
aws ecs describe-services \
    --cluster cicd-cluster \
    --services cicd-service \
    --query 'services[0].events[:5]'

# Check task definition
aws ecs describe-task-definition \
    --task-definition cicd-task \
    --query 'taskDefinition.{Family:family,Revision:revision,Status:status}'

# Check task logs
aws logs get-log-events \
    --log-group-name /ecs/cicd-task \
    --log-stream-name "ecs/cicd-task/$(date +%Y/%m/%d)"
```

**Issue: Tasks keep stopping**
```bash
# Check stopped tasks
aws ecs list-tasks \
    --cluster cicd-cluster \
    --desired-status STOPPED \
    --query 'taskArns[:3]'

# Get stop reason
aws ecs describe-tasks \
    --cluster cicd-cluster \
    --tasks $STOPPED_TASK_ARN \
    --query 'tasks[0].{StoppedReason:stoppedReason,StoppedAt:stoppedAt}'
```

### 10.3 Network and Connectivity Issues

```bash
# Check security groups
aws ec2 describe-security-groups \
    --group-ids $SECURITY_GROUP_ID \
    --query 'SecurityGroups[0].IpPermissions'

# Check subnet configuration
aws ec2 describe-subnets \
    --subnet-ids $SUBNET_ID \
    --query 'Subnets[0].{AvailabilityZone:AvailabilityZone,CidrBlock:CidrBlock,MapPublicIpOnLaunch:MapPublicIpOnLaunch}'

# Test connectivity from task
aws ecs execute-command \
    --cluster cicd-cluster \
    --task $TASK_ARN \
    --container cicd-container \
    --interactive \
    --command "/bin/sh"
```

---

## 11. Security Testing

### 11.1 Security Validation Checklist

- [ ] **Secret Scanning**: No hardcoded secrets in code
- [ ] **SAST**: No critical security vulnerabilities
- [ ] **SCA**: No high/critical dependency vulnerabilities
- [ ] **Container Scanning**: Base image has no critical CVEs
- [ ] **SBOM**: Software Bill of Materials generated
- [ ] **IAM**: Least privilege access configured
- [ ] **Network**: Security groups properly configured
- [ ] **Logging**: All security events logged

### 11.2 Penetration Testing

```bash
# Basic security tests
# Test for common vulnerabilities
curl -X POST http://$PUBLIC_IP:3000/api/test \
    -H "Content-Type: application/json" \
    -d '{"test": "<script>alert(1)</script>"}'

# Test rate limiting
for i in {1..100}; do
    curl -s -o /dev/null -w "%{http_code}\n" http://$PUBLIC_IP:3000/
done

# Test SSL/TLS (if HTTPS enabled)
nmap --script ssl-enum-ciphers -p 443 $PUBLIC_IP
```

### 11.3 Compliance Verification

```bash
# Generate compliance report
echo "=== Security Compliance Report ===" > compliance-report.txt
echo "Date: $(date)" >> compliance-report.txt
echo "" >> compliance-report.txt

# Check secret scanning
echo "Secret Scanning: $([ -s gitleaks-report.json ] && echo 'FAIL' || echo 'PASS')" >> compliance-report.txt

# Check vulnerability scanning
echo "Vulnerability Scanning: $(trivy image --exit-code 1 --quiet $IMAGE_NAME && echo 'PASS' || echo 'FAIL')" >> compliance-report.txt

# Check SBOM generation
echo "SBOM Generated: $([ -f sbom.json ] && echo 'PASS' || echo 'FAIL')" >> compliance-report.txt

cat compliance-report.txt
```

---

## 12. Cleanup and Maintenance

### 12.1 Terraform Resource Cleanup

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy

# Or destroy specific resources
terraform destroy -target=module.jenkins
terraform destroy -target=module.app_server
terraform destroy -target=module.ecr  # if ECR module exists
```

### 12.2 Manual ECR Cleanup (if created outside Terraform)

```bash
# Clean up ECR repository if created manually
aws ecr delete-repository \
    --repository-name cicd-node-app \
    --force
```

### 12.3 Maintenance Tasks

```bash
# Update Terraform modules
terraform get -update

# Clean up old ECR images (if ECR exists)
ECR_REPO_URI=$(terraform output -raw ecr_repository_url 2>/dev/null)
if [ ! -z "$ECR_REPO_URI" ]; then
    aws ecr list-images \
        --repository-name $(echo $ECR_REPO_URI | cut -d'/' -f2) \
        --filter tagStatus=TAGGED \
        --query 'imageIds[10:]' \
        --output json > old-images.json

    if [ -s old-images.json ] && [ "$(cat old-images.json)" != "[]" ]; then
        aws ecr batch-delete-image \
            --repository-name $(echo $ECR_REPO_URI | cut -d'/' -f2) \
            --image-ids file://old-images.json
    fi
fi

# Update application server packages
APP_SERVER_IP=$(terraform output -raw app_server_public_ip)
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$APP_SERVER_IP \
    "sudo yum update -y"

# Update Jenkins server
JENKINS_IP=$(terraform output -raw jenkins_public_ip)
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$JENKINS_IP \
    "sudo yum update -y"
```

### 12.4 Security Updates

```bash
# Update base image regularly
docker pull node:20-alpine

# Update security tools
docker pull zricethezav/gitleaks:latest
docker pull aquasec/trivy:latest
docker pull anchore/syft:latest

# Update dependencies
npm audit fix
npm update

# Update server security patches
for SERVER_IP in $(terraform output -raw jenkins_public_ip) $(terraform output -raw app_server_public_ip); do
    ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$SERVER_IP \
        "sudo yum update -y --security"
done
```

---

## Quick Reference Commands

```bash
# Infrastructure Status
terraform output

# Application Status
APP_IP=$(terraform output -raw app_server_public_ip)
curl -f http://$APP_IP:3000/health

# Jenkins Access
echo "Jenkins: http://$(terraform output -raw jenkins_public_ip):8080"

# View Application Logs
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$(terraform output -raw app_server_public_ip) "sudo journalctl -u node-app -f"

# Emergency Rollback (EC2)
ssh -i ~/.ssh/$(terraform output -raw key_name).pem ec2-user@$(terraform output -raw app_server_public_ip) "sudo systemctl restart node-app"

# Infrastructure Cleanup
terraform destroy
```

---

**🔒 Security First**: This pipeline implements multiple security gates to ensure only secure, compliant code reaches production.

**📊 Monitoring**: Comprehensive logging and monitoring ensure visibility into application and infrastructure health.

**🚀 Automation**: Fully automated CI/CD pipeline with manual override capabilities for emergency situations. --json > npm-audit-report.json

# Snyk scan
npx snyk test --severity-threshold=high --json > snyk-report.json

# Check for high/critical vulnerabilities
npm audit --audit-level=high || echo "❌ High/Critical vulnerabilities found"
npx snyk test --severity-threshold=high || echo "❌ Snyk found high/critical issues"
```

### 7.4 Container Image Scanning with Trivy

```bash
# Build image first
docker build -t cicd-node-app:test .

# Scan with Trivy
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image \
    --format json \
    --output trivy-report.json \
    cicd-node-app:test

# Check for critical/high vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    cicd-node-app:test
```

### 7.5 SBOM Generation with Syft

```bash
# Generate CycloneDX SBOM
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/syft:latest cicd-node-app:test \
    -o cyclonedx-json > sbom-cyclonedx.json

# Generate SPDX SBOM
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/syft:latest cicd-node-app:test \
    -o spdx-json > sbom-spdx.json

# Verify SBOM content
jq '.components | length' sbom-cyclonedx.json
```

---

## 8. Deployment Workflows

### 8.1 Standard Deployment Flow

```bash
# 1. Code changes
git add .
git commit -m "feat: new feature"
git push origin main

# 2. Jenkins pipeline triggers automatically
# 3. Security scans run (all must pass)
# 4. Image built and pushed to ECR
# 5. ECS task definition updated
# 6. ECS service updated with rolling deployment
```

### 8.2 Manual Deployment

```bash
# Build and push manually
docker build -t cicd-node-app:manual .
docker tag cicd-node-app:manual $ECR_REGISTRY/cicd-node-app:manual

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

# Push image
docker push $ECR_REGISTRY/cicd-node-app:manual

# Update ECS service
aws ecs update-service \
    --cluster cicd-cluster \
    --service cicd-service \
    --force-new-deployment
```

### 8.3 Rollback Procedure

```bash
# List task definition revisions
aws ecs list-task-definitions \
    --family-prefix cicd-task \
    --status ACTIVE

# Rollback to previous revision
aws ecs update-service \
    --cluster cicd-cluster \
    --service cicd-service \
    --task-definition cicd-task:N  # Replace N with previous revision

# Verify rollback
aws ecs describe-services \
    --cluster cicd-cluster \
    --services cicd-service \
    --query 'services[0].taskDefinition'
```

### 8.4 Blue-Green Deployment

```bash
# Create new service version
aws ecs create-service \
    --cluster cicd-cluster \
    --service-name cicd-service-green \
    --task-definition cicd-task:latest \
    --desired-count 2 \
    --launch-type FARGATE

# Test green environment
# Switch traffic (update load balancer target groups)
# Decommission blue environment
aws ecs delete-service \
    --cluster cicd-cluster \
    --service cicd-service-blue \
    --force
```

---

## 9. Monitoring and Logging

### 9.1 CloudWatch Logs

```bash
# View application logs
aws logs tail /ecs/cicd-task --follow

# Filter error logs
aws logs filter-log-events \
    --log-group-name /ecs/cicd-task \
    --filter-pattern "ERROR"

# Get log insights
aws logs start-query \
    --log-group-name /ecs/cicd-task \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

### 9.2 ECS Service Monitoring

```bash
# Service metrics
aws ecs describe-services \
    --cluster cicd-cluster \
    --services cicd-service \
    --query 'services[0].{Running:runningCount,Desired:desiredCount,Pending:pendingCount}'

# Task health
aws ecs describe-tasks \
    --cluster cicd-cluster \
    --tasks $(aws ecs list-tasks --cluster cicd-cluster --service-name cicd-service --query 'taskArns' --output text) \
    --query 'tasks[*].{TaskArn:taskArn,LastStatus:lastStatus,HealthStatus:healthStatus}'
```

### 9.3 Application Health Checks

```bash
# Get service endpoint (if using load balancer)
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names cicd-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Health check
curl http://$ALB_DNS/health
# Expected: {"status":"healthy"}

# Application info
curl http://$ALB_DNS/api/info
# Expected: {"version":"1.0.0","deploymentTime":"..."}
```

---

## 10. Troubleshooting

### 10.1 Pipeline Failures

**Secret Scan Failure:**
```bash
# Check Gitleaks report
cat gitleaks-report.json
# Remove secrets and commit
git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch path/to/secret/file' --prune-empty --tag-name-filter cat -- --all
```

**SAST Failure:**
```bash
# Check SonarQube issues
curl -u <token>: "http://localhost:9000/api/issues/search?componentKeys=cicd-node-app&severities=BLOCKER,CRITICAL"
# Fix code quality issues
```

**SCA Failure:**
```bash
# Check vulnerable dependencies
npm audit --audit-level=high
# Update dependencies
npm update
npm audit fix
```

**Container Scan Failure:**
```bash
# Check Trivy report
cat trivy-report.json | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL" or .Severity=="HIGH")'
# Update base image or dependencies
```

### 10.2 ECS Deployment Issues

**Task Won't Start:**
```bash
# Check task definition
aws ecs describe-task-definition --task-definition cicd-task

# Check stopped tasks
aws ecs describe-tasks \
    --cluster cicd-cluster \
    --tasks $(aws ecs list-tasks --cluster cicd-cluster --desired-status STOPPED --query 'taskArns[0]' --output text)
```

**Service Unhealthy:**
```bash
# Check service events
aws ecs describe-services \
    --cluster cicd-cluster \
    --services cicd-service \
    --query 'services[0].events[0:5]'

# Check task logs
aws logs tail /ecs/cicd-task --since 1h
```

### 10.3 ECR Issues

**Push Failures:**
```bash
# Re-authenticate
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

# Check repository permissions
aws ecr describe-repositories --repository-names cicd-node-app
```

---

## 11. Security Testing

### 11.1 Inject Vulnerable Dependency

```bash
# Add vulnerable package to test pipeline blocking
npm install lodash@4.17.4  # Known vulnerable version

# Commit and push
git add package*.json
git commit -m "test: add vulnerable dependency"
git push origin main

# Pipeline should fail at SCA stage
# Expected: "❌ High/Critical vulnerabilities found"
```

### 11.2 Inject Secret to Test Detection

```bash
# Create test file with fake secret
echo "AWS_SECRET_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE" > test-secret.txt

# Commit and push
git add test-secret.txt
git commit -m "test: add secret for testing"
git push origin main

# Pipeline should fail at secret scanning stage
# Expected: "❌ CRITICAL: Secrets detected!"
```

### 11.3 Fix and Verify

```bash
# Remove vulnerable dependency
npm uninstall lodash
npm install lodash@latest

# Remove secret file
git rm test-secret.txt

# Commit fixes
git add .
git commit -m "fix: remove vulnerabilities and secrets"
git push origin main

# Pipeline should now pass
# Expected: "✅ All quality gates passed"
```

---

## 12. Cleanup and Maintenance

### 12.1 ECR Lifecycle Management

```bash
# Create lifecycle policy
cat > ecr-lifecycle-policy.json << EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "tagged",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

# Apply lifecycle policy
aws ecr put-lifecycle-policy \
    --repository-name cicd-node-app \
    --lifecycle-policy-text file://ecr-lifecycle-policy.json
```

### 12.2 ECS Task Definition Cleanup

```bash
# List all task definitions
aws ecs list-task-definitions --family-prefix cicd-task

# Deregister old revisions (keep last 5)
for revision in $(aws ecs list-task-definitions \
    --family-prefix cicd-task \
    --status ACTIVE \
    --query 'taskDefinitionArns[0:-5]' \
    --output text); do
    aws ecs deregister-task-definition --task-definition $revision
done
```

### 12.3 CloudWatch Logs Cleanup

```bash
# Set log retention (already done in setup)
aws logs put-retention-policy \
    --log-group-name /ecs/cicd-task \
    --retention-in-days 7

# Manual cleanup if needed
aws logs delete-log-group --log-group-name /ecs/cicd-task-old
```

### 12.4 Complete Infrastructure Cleanup

```bash
# Delete ECS service
aws ecs update-service \
    --cluster cicd-cluster \
    --service cicd-service \
    --desired-count 0

aws ecs delete-service \
    --cluster cicd-cluster \
    --service cicd-service

# Delete ECS cluster
aws ecs delete-cluster --cluster cicd-cluster

# Delete ECR repository
aws ecr delete-repository \
    --repository-name cicd-node-app \
    --force

# Delete CloudWatch log group
aws logs delete-log-group --log-group-name /ecs/cicd-task

# Delete IAM roles
aws iam detach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam delete-role --role-name ecsTaskExecutionRole
aws iam delete-role --role-name ecsTaskRole
```

---

## Quick Reference Commands

### Pipeline Status
```bash
# Check last build status
curl -u admin:password http://jenkins-url:8080/job/secure-cicd-pipeline/lastBuild/api/json

# Trigger manual build
curl -u admin:password -X POST http://jenkins-url:8080/job/secure-cicd-pipeline/build
```

### ECS Quick Status
```bash
# Service overview
aws ecs describe-services --cluster cicd-cluster --services cicd-service --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# Latest deployment
aws ecs describe-services --cluster cicd-cluster --services cicd-service --query 'services[0].deployments[0]'
```

### Security Scan Summary
```bash
# Quick security check
echo "=== Security Scan Results ==="
echo "Secrets: $([ -f gitleaks-report.json ] && echo "❌ Found" || echo "✅ Clean")"
echo "SAST: $(curl -s -u token: 'http://localhost:9000/api/qualitygates/project_status?projectKey=cicd-node-app' | jq -r '.projectStatus.status')"
echo "SCA: $(npm audit --audit-level=high > /dev/null 2>&1 && echo "✅ Clean" || echo "❌ Issues")"
echo "Container: $([ -f trivy-report.json ] && echo "❌ Vulnerabilities" || echo "✅ Clean")"
```

---

**🎯 Success Indicators:**
- ✅ All security scans pass
- ✅ Image pushed to ECR with version tag
- ✅ ECS service running with new task definition
- ✅ Application accessible and healthy
- ✅ CloudWatch logs flowing
- ✅ SBOM artifacts generated and archived

**📊 Estimated Costs (us-east-1):**
- ECS Fargate (2 tasks): ~$25/month
- ECR storage: ~$1/month
- CloudWatch logs: ~$2/month
- **Total**: ~$28/month