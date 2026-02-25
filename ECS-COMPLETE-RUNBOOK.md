# Complete ECS Deployment Runbook - Start to Finish

> **Complete CI/CD Pipeline with Amazon ECS Fargate Deployment**
>
> **Stack:** Node.js app · Jenkins · Amazon ECR · Amazon ECS Fargate · Security Scanning · Terraform

---

## Table of Contents

1. [Quick Start Guide](#1-quick-start-guide)
2. [Prerequisites](#2-prerequisites)
3. [Infrastructure Setup](#3-infrastructure-setup)
4. [ECS Service Deployment](#4-ecs-service-deployment)
5. [Jenkins Pipeline Configuration](#5-jenkins-pipeline-configuration)
6. [Application Deployment](#6-application-deployment)
7. [Monitoring & Health Checks](#7-monitoring--health-checks)
8. [Troubleshooting](#8-troubleshooting)
9. [Maintenance & Cleanup](#9-maintenance--cleanup)

---

## 1. Quick Start Guide

### 🚀 Complete Deployment (15 minutes)

```bash
# 1. Deploy Infrastructure
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply -auto-approve

# 2. Setup ECS Service
cd ..
chmod +x setup-ecs.sh
./setup-ecs.sh

# 3. Configure Jenkins Pipeline
# Access Jenkins at http://$(terraform output -raw jenkins_public_ip):8080
# Create pipeline job using Jenkinsfile.ecs

# 4. Deploy Application
# Push code changes or trigger manual build in Jenkins
```

### ✅ Success Indicators
- ECS cluster running with 1 task
- Application accessible at public IP:5000
- Health check returns `{"status":"healthy"}`
- Jenkins pipeline completes successfully

---

## 2. Prerequisites

### 2.1 Required Tools
```bash
# Verify installations
aws --version          # AWS CLI v2
docker --version       # Docker Engine
terraform --version    # Terraform >= 1.0
node --version         # Node.js 20+
jq --version          # JSON processor
```

### 2.2 AWS Configuration
```bash
# Configure AWS CLI
aws configure
# Enter: Access Key, Secret Key, Region (us-east-1), Output (json)

# Verify access
aws sts get-caller-identity
aws ecs list-clusters || echo "No ECS clusters yet"
```

### 2.3 Required AWS Permissions
Your AWS user/role needs these permissions:
- `AmazonECS_FullAccess`
- `AmazonEC2ContainerRegistryFullAccess`
- `IAMFullAccess` (for role creation)
- `AmazonVPCFullAccess`
- `CloudWatchFullAccess`

---

## 3. Infrastructure Setup

### 3.1 Configure Terraform Variables
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
cat > terraform.tfvars << EOF
aws_region = "us-east-1"
project_name = "cicd-pipeline"
environment = "dev"
allowed_ips = ["$(curl -s ifconfig.me)/32"]  # Your public IP
jenkins_admin_password = "your-secure-password"
EOF
```

### 3.2 Deploy Base Infrastructure
```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Deploy infrastructure
terraform apply -auto-approve

# Save outputs for reference
terraform output > ../infrastructure-outputs.txt
```

### 3.3 Verify Infrastructure
```bash
# Check outputs
terraform output

# Expected outputs:
# - jenkins_public_ip
# - ecs_cluster_name
# - ecr_repository_url
# - ecs_task_execution_role_arn
# - public_subnets
# - vpc_id
```

---

## 4. ECS Service Deployment

### 4.1 Automated ECS Setup
```bash
cd ..  # Back to project root
chmod +x setup-ecs.sh
./setup-ecs.sh
```

This script will:
- ✅ Build and push initial Docker image to ECR
- ✅ Create ECS task definition
- ✅ Create ECS service with Fargate launch type
- ✅ Wait for service to stabilize
- ✅ Display application URL

### 4.2 Manual ECS Setup (Alternative)
```bash
# Get Terraform outputs
CLUSTER_NAME=$(cd terraform && terraform output -raw ecs_cluster_name)
ECR_REPO_URL=$(cd terraform && terraform output -raw ecr_repository_url)
AWS_REGION="us-east-1"

# Build and push image
docker build -t cicd-node-app:latest .
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URL
docker tag cicd-node-app:latest $ECR_REPO_URL:latest
docker push $ECR_REPO_URL:latest

# Register task definition
envsubst < ecs-task-definition.json > ecs-task-definition-resolved.json
aws ecs register-task-definition --cli-input-json file://ecs-task-definition-resolved.json

# Create service
SUBNETS=$(cd terraform && terraform output -json public_subnets | jq -r '.[]' | tr '\n' ',' | sed 's/,$//')
SECURITY_GROUP=$(cd terraform && terraform output -raw ecs_service_security_group_id)

aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name cicd-service \
    --task-definition cicd-task:1 \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}"
```

### 4.3 Verify ECS Deployment
```bash
# Check service status
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services cicd-service \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# Get application URL
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "🌐 Application URL: http://$PUBLIC_IP:5000"
echo "❤️  Health check: http://$PUBLIC_IP:5000/health"

# Test application
curl -f http://$PUBLIC_IP:5000/health
```

---

## 5. Jenkins Pipeline Configuration

### 5.1 Access Jenkins
```bash
# Get Jenkins URL
JENKINS_IP=$(cd terraform && terraform output -raw jenkins_public_ip)
echo "Jenkins URL: http://$JENKINS_IP:8080"

# Get initial admin password (if needed)
ssh -i ~/.ssh/$(cd terraform && terraform output -raw key_name).pem ec2-user@$JENKINS_IP \
    "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
```

### 5.2 Required Jenkins Credentials
Navigate to **Manage Jenkins → Credentials → Global**:

| Credential ID | Type | Value |
|---------------|------|-------|
| `aws-account-id` | Secret text | Your 12-digit AWS Account ID |
| `aws-credentials` | AWS Credentials | AWS Access Key + Secret Key |
| `ecr-repo-uri` | Secret text | ECR repository URI from Terraform |

```bash
# Get values for credentials
echo "AWS Account ID: $(aws sts get-caller-identity --query Account --output text)"
echo "ECR Repository URI: $(cd terraform && terraform output -raw ecr_repository_url)"
```

### 5.3 Create Pipeline Job
1. **Jenkins Dashboard → New Item**
2. **Name:** `ecs-cicd-pipeline`
3. **Type:** Pipeline
4. **Pipeline script from SCM:**
   - SCM: Git
   - Repository URL: `https://github.com/YOUR_USERNAME/YOUR_REPO.git`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile.ecs`

### 5.4 Switch to ECS Pipeline
```bash
# Rename Jenkinsfile to use ECS deployment
mv Jenkinsfile Jenkinsfile.ec2
mv Jenkinsfile.ecs Jenkinsfile

# Commit changes
git add .
git commit -m "Switch to ECS deployment pipeline"
git push origin main
```

---

## 6. Application Deployment

### 6.1 Automated Deployment (Recommended)
```bash
# Make code changes
echo "console.log('Updated application');" >> app.js

# Commit and push
git add .
git commit -m "feat: update application"
git push origin main

# Jenkins pipeline will automatically:
# 1. Run security scans
# 2. Build Docker image
# 3. Push to ECR with build number tag
# 4. Update ECS task definition
# 5. Deploy to ECS service
```

### 6.2 Manual Deployment
```bash
# Build and tag image
BUILD_NUMBER=$(date +%s)
docker build -t cicd-node-app:$BUILD_NUMBER .

# Push to ECR
ECR_REPO_URL=$(cd terraform && terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO_URL
docker tag cicd-node-app:$BUILD_NUMBER $ECR_REPO_URL:$BUILD_NUMBER
docker push $ECR_REPO_URL:$BUILD_NUMBER

# Update task definition
sed "s|:latest|:$BUILD_NUMBER|g" ecs-task-definition.json > ecs-task-definition-new.json
aws ecs register-task-definition --cli-input-json file://ecs-task-definition-new.json

# Update service
CLUSTER_NAME=$(cd terraform && terraform output -raw ecs_cluster_name)
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service cicd-service \
    --task-definition cicd-task

# Wait for deployment
aws ecs wait services-stable --cluster $CLUSTER_NAME --services cicd-service
```

### 6.3 Deployment Verification
```bash
# Check service status
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services cicd-service \
    --query 'services[0].deployments[0].{Status:status,TaskDefinition:taskDefinition,DesiredCount:desiredCount,RunningCount:runningCount}'

# Get new application URL
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

# Test deployment
curl -f http://$PUBLIC_IP:5000/health
curl -f http://$PUBLIC_IP:5000/
```

---

## 7. Monitoring & Health Checks

### 7.1 Application Health Monitoring
```bash
# Get current application IP
get_app_ip() {
    CLUSTER_NAME=$(cd terraform && terraform output -raw ecs_cluster_name)
    TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text)
    ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
    aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Association.PublicIp' --output text
}

APP_IP=$(get_app_ip)
echo "Application IP: $APP_IP"

# Health checks
curl -f http://$APP_IP:5000/health || echo "❌ Health check failed"
curl -f http://$APP_IP:5000/ || echo "❌ Application not responding"
```

### 7.2 CloudWatch Logs
```bash
# View application logs
aws logs tail /ecs/cicd-task --follow

# Filter error logs
aws logs filter-log-events \
    --log-group-name /ecs/cicd-task \
    --filter-pattern "ERROR" \
    --start-time $(date -d '1 hour ago' +%s)000

# Get recent logs
aws logs describe-log-streams \
    --log-group-name /ecs/cicd-task \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text | xargs -I {} aws logs get-log-events --log-group-name /ecs/cicd-task --log-stream-name {}
```

### 7.3 ECS Service Monitoring
```bash
# Service overview
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services cicd-service \
    --query 'services[0].{ServiceName:serviceName,Status:status,TaskDefinition:taskDefinition,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}'

# Task details
aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks $(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text) \
    --query 'tasks[0].{TaskArn:taskArn,LastStatus:lastStatus,HealthStatus:healthStatus,CreatedAt:createdAt}'

# Service events (troubleshooting)
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services cicd-service \
    --query 'services[0].events[0:5]'
```

---

## 8. Troubleshooting

### 8.1 Common ECS Issues

**Issue: Service fails to start**
```bash
# Check service events
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services cicd-service \
    --query 'services[0].events[0:3]'

# Check task definition
aws ecs describe-task-definition \
    --task-definition cicd-task \
    --query 'taskDefinition.{Family:family,Revision:revision,Status:status}'

# Check stopped tasks
aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --desired-status STOPPED \
    --query 'taskArns[0:3]' | xargs -I {} aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks {} --query 'tasks[0].{StoppedReason:stoppedReason,StoppedAt:stoppedAt}'
```

**Issue: Tasks keep stopping**
```bash
# Check container logs
aws logs get-log-events \
    --log-group-name /ecs/cicd-task \
    --log-stream-name $(aws logs describe-log-streams --log-group-name /ecs/cicd-task --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text) \
    --start-time $(date -d '10 minutes ago' +%s)000

# Check health check failures
aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks $(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text) \
    --query 'tasks[0].containers[0].{Name:name,LastStatus:lastStatus,HealthStatus:healthStatus,Reason:reason}'
```

**Issue: Cannot access application**
```bash
# Check security group rules
SECURITY_GROUP=$(cd terraform && terraform output -raw ecs_service_security_group_id)
aws ec2 describe-security-groups \
    --group-ids $SECURITY_GROUP \
    --query 'SecurityGroups[0].IpPermissions'

# Check if task has public IP
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text)
aws ecs describe-tasks \
    --cluster $CLUSTER_NAME \
    --tasks $TASK_ARN \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
    --output text | xargs -I {} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp'
```

### 8.2 Pipeline Issues

**Issue: ECR push fails**
```bash
# Re-authenticate with ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(cd terraform && terraform output -raw ecr_repository_url)

# Check repository exists
aws ecr describe-repositories --repository-names cicd-node-app

# Check image exists
aws ecr list-images --repository-name cicd-node-app
```

**Issue: Task definition registration fails**
```bash
# Validate task definition JSON
cat ecs-task-definition.json | jq .

# Check IAM roles exist
aws iam get-role --role-name ecsTaskExecutionRole
aws iam get-role --role-name ecsTaskRole

# Check log group exists
aws logs describe-log-groups --log-group-name-prefix /ecs/cicd-task
```

### 8.3 Network Issues
```bash
# Check VPC and subnets
VPC_ID=$(cd terraform && terraform output -raw vpc_id)
aws ec2 describe-vpcs --vpc-ids $VPC_ID

# Check subnet configuration
SUBNETS=$(cd terraform && terraform output -json public_subnets | jq -r '.[]')
for subnet in $SUBNETS; do
    aws ec2 describe-subnets --subnet-ids $subnet --query 'Subnets[0].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}'
done

# Check internet gateway
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID"
```

---

## 9. Maintenance & Cleanup

### 9.1 Rollback Deployment
```bash
# List task definition revisions
aws ecs list-task-definitions \
    --family-prefix cicd-task \
    --status ACTIVE

# Rollback to previous revision
PREVIOUS_REVISION=$(aws ecs list-task-definitions --family-prefix cicd-task --status ACTIVE --query 'taskDefinitionArns[-2]' --output text)
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service cicd-service \
    --task-definition $PREVIOUS_REVISION

# Wait for rollback
aws ecs wait services-stable --cluster $CLUSTER_NAME --services cicd-service
```

### 9.2 Scale Service
```bash
# Scale up
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service cicd-service \
    --desired-count 2

# Scale down
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service cicd-service \
    --desired-count 1
```

### 9.3 Clean Up Old Images
```bash
# List images
aws ecr list-images --repository-name cicd-node-app

# Delete old images (keep last 10)
aws ecr list-images \
    --repository-name cicd-node-app \
    --filter tagStatus=TAGGED \
    --query 'imageIds[10:]' \
    --output json > old-images.json

if [ -s old-images.json ] && [ "$(cat old-images.json)" != "[]" ]; then
    aws ecr batch-delete-image \
        --repository-name cicd-node-app \
        --image-ids file://old-images.json
fi
```

### 9.4 Complete Cleanup
```bash
# Delete ECS service
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service cicd-service \
    --desired-count 0

aws ecs delete-service \
    --cluster $CLUSTER_NAME \
    --service cicd-service

# Delete ECS cluster
aws ecs delete-cluster --cluster $CLUSTER_NAME

# Destroy Terraform infrastructure
cd terraform
terraform destroy -auto-approve
```

---

## Quick Reference Commands

### Status Check
```bash
# Infrastructure status
cd terraform && terraform output

# ECS service status
CLUSTER_NAME=$(cd terraform && terraform output -raw ecs_cluster_name)
aws ecs describe-services --cluster $CLUSTER_NAME --services cicd-service --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# Application URL
get_app_ip() {
    TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text)
    ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
    aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Association.PublicIp' --output text
}
echo "App URL: http://$(get_app_ip):5000"
```

### Emergency Commands
```bash
# Force new deployment
aws ecs update-service --cluster $CLUSTER_NAME --service cicd-service --force-new-deployment

# View logs
aws logs tail /ecs/cicd-task --follow

# Restart service (scale to 0 then back to 1)
aws ecs update-service --cluster $CLUSTER_NAME --service cicd-service --desired-count 0
sleep 30
aws ecs update-service --cluster $CLUSTER_NAME --service cicd-service --desired-count 1
```

---

## Success Checklist

- [ ] ✅ Terraform infrastructure deployed
- [ ] ✅ ECS cluster created and running
- [ ] ✅ ECR repository created with initial image
- [ ] ✅ ECS service running with 1 task
- [ ] ✅ Application accessible at public IP:5000
- [ ] ✅ Health check endpoint returns healthy status
- [ ] ✅ Jenkins pipeline configured with ECS deployment
- [ ] ✅ CloudWatch logs flowing
- [ ] ✅ Security scans passing in pipeline
- [ ] ✅ Automated deployments working

**🎯 Total Setup Time: ~15-20 minutes**
**💰 Estimated Monthly Cost: ~$25-30 (Fargate + ECR + CloudWatch)**

---

**🚀 You now have a complete, production-ready ECS deployment pipeline with security scanning, automated deployments, and comprehensive monitoring!**