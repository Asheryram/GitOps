# Complete GitOps CI/CD Pipeline - Project Documentation

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Technology Stack](#technology-stack)
4. [Project Structure](#project-structure)
5. [Prerequisites](#prerequisites)
6. [Quick Start Guide](#quick-start-guide)
7. [Detailed Setup Instructions](#detailed-setup-instructions)
8. [Pipeline Variants](#pipeline-variants)
9. [Security Features](#security-features)
10. [Operations Guide](#operations-guide)
11. [Troubleshooting](#troubleshooting)
12. [Cost Analysis](#cost-analysis)
13. [Maintenance](#maintenance)

---

## Project Overview

### Purpose
Complete end-to-end CI/CD pipeline solution that automates infrastructure provisioning, continuous integration, security scanning, and deployment of containerized Node.js applications on AWS.

### Key Features
- **Infrastructure as Code**: Terraform modules for reproducible AWS infrastructure
- **Automated CI/CD**: Jenkins pipeline with 15 stages from checkout to deployment
- **Security-First**: Multiple security scanning tools (Gitleaks, SonarQube, Trivy, Snyk)
- **Container Orchestration**: Support for both EC2 and ECS deployments
- **SBOM Generation**: Software Bill of Materials in CycloneDX and SPDX formats
- **Quality Gates**: Configurable security gates (warn-only or strict mode)

### Target Audience
- DevOps Engineers setting up CI/CD pipelines
- Development Teams automating deployment workflows
- Cloud Architects designing secure AWS infrastructure
- Security Teams implementing DevSecOps practices

---

## Architecture

### High-Level Architecture

```
┌─────────────┐
│  Developer  │
└──────┬──────┘
       │ git push
       ▼
┌─────────────────┐
│     GitHub      │
└────────┬────────┘
         │ webhook/poll
         ▼
┌──────────────────────────────────────────────────────────┐
│              Jenkins (Docker on EC2)                      │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Pipeline Stages:                                   │  │
│  │ 1. Checkout                                        │  │
│  │ 2. Secret Scanning (Gitleaks)                      │  │
│  │ 3. Install Dependencies                            │  │
│  │ 4. SAST (SonarQube)                                │  │
│  │ 5. SCA (npm audit + Snyk)                          │  │
│  │ 6. Unit Tests (Jest)                               │  │
│  │ 7. Build Docker Image                              │  │
│  │ 8. Generate SBOM (Syft)                            │  │
│  │ 9. Container Scan (Trivy)                          │  │
│  │ 10. Quality Gate Check                             │  │
│  │ 11. Push to ECR                                    │  │
│  │ 12. Update ECS Task Definition                     │  │
│  │ 13. Deploy to ECS                                  │  │
│  │ 14. Verify Deployment                              │  │
│  │ 15. Cleanup Old Images                             │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │   Amazon ECR   │
              └────────┬───────┘
                       │
                       ▼
              ┌────────────────┐
              │   Amazon ECS   │
              │   (Fargate)    │
              └────────┬───────┘
                       │
                       ▼
              ┌────────────────┐
              │  Application   │
              │   (Port 5000)  │
              └────────────────┘
```

### Network Architecture

```
VPC (10.0.0.0/16)
├── Public Subnet 1 (10.0.1.0/24) - AZ 1
│   └── Jenkins EC2 Instance
├── Public Subnet 2 (10.0.2.0/24) - AZ 2
│   └── App Server EC2 Instance
├── Private Subnet 1 (10.0.10.0/24) - AZ 1
│   └── ECS Tasks (Fargate)
└── Private Subnet 2 (10.0.20.0/24) - AZ 2
    └── ECS Tasks (Fargate)

Internet Gateway → Route Tables → Subnets
Security Groups: Jenkins SG ↔ App SG ↔ ECS SG
```

### Component Relationships

```
Terraform Root Module
├── VPC Module (network foundation)
├── Security Module (firewall rules)
├── Keypair Module (SSH keys)
├── Jenkins Module (CI/CD server)
├── EC2 Module (app servers)
├── ECR Module (container registry)
└── ECS Module (container orchestration)
```

---

## Technology Stack

### Core Technologies
- **Node.js**: v20.x (application runtime)
- **Express.js**: v4.18.2 (web framework)
- **Docker**: Latest stable (containerization)
- **Terraform**: >= 1.0 (infrastructure as code)
- **Jenkins**: LTS (CI/CD automation)

### AWS Services
- **EC2**: t3.micro/small/medium instances
- **VPC**: Custom networking with public/private subnets
- **ECR**: Docker container registry
- **ECS**: Container orchestration (Fargate launch type)
- **Security Groups**: Network access control
- **CloudWatch**: Monitoring and logging

### Security Tools
- **Gitleaks**: Secret detection in source code
- **SonarQube**: Static Application Security Testing (SAST)
- **npm audit**: Dependency vulnerability scanning
- **Snyk**: Software Composition Analysis (SCA)
- **Trivy**: Container image vulnerability scanning
- **Syft**: SBOM generation

### Testing & Quality
- **Jest**: v29.5.0 (unit testing framework)
- **Supertest**: v6.3.3 (HTTP assertions)
- **SonarQube Quality Gates**: Code quality enforcement

---

## Project Structure

```
Gitops/
├── app.js                              # Express.js application
├── app.test.js                         # Jest test suite
├── package.json                        # Node.js dependencies
├── Dockerfile                          # Container image definition
│
├── Jenkinsfile                         # Main pipeline (warn-only mode)
├── Jenkinsfile-strict                  # Strict mode (blocks on findings)
├── Jenkinsfile-warn-only               # Warn-only mode (never blocks)
├── Jenkinsfile.ec2                     # EC2 deployment variant
│
├── README.md                           # Main documentation
├── PROJECT-DOCUMENTATION.md            # This file
├── SETUP-GUIDE.md                      # Step-by-step setup
├── RUNBOOK.md                          # Operations guide
├── GITOPS-RUNBOOK.md                   # GitOps workflow
├── ECS-COMPLETE-RUNBOOK.md             # ECS deployment guide
│
├── sonar-project.properties            # SonarQube configuration
├── trivy.yaml                          # Trivy scanner config
├── .gitleaks.toml                      # Gitleaks rules
├── .dockerignore                       # Docker build exclusions
├── .gitignore                          # Git exclusions
│
├── ecs-task-definition.json            # ECS task configuration
├── ecs-service-definition.json         # ECS service configuration
├── cloudwatch-alarms.json              # CloudWatch monitoring
├── ecr-lifecycle-policy.json           # ECR image retention
│
├── setup-ecs.sh                        # ECS setup automation
├── deploy-ecs.sh                       # ECS deployment script
├── validate-deployment.sh              # Deployment verification
├── test-quality-gates.sh               # Quality gate testing
│
├── architecture-diagram.png            # System architecture
├── architecture-diagram.drawio         # Editable diagram
│
├── screenshots/                        # Documentation images
│   ├── successful_pipeline.png
│   └── successfull_app_deployment_site.png
│
├── terraform/                          # Infrastructure as Code
│   ├── main.tf                         # Root module
│   ├── variables.tf                    # Input variables
│   ├── outputs.tf                      # Output values
│   ├── terraform.tfvars.example        # Example configuration
│   │
│   ├── modules/                        # Reusable modules
│   │   ├── vpc/                        # Network infrastructure
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── security/                   # Security groups
│   │   ├── keypair/                    # SSH key generation
│   │   ├── jenkins/                    # Jenkins server
│   │   ├── ec2/                        # Application servers
│   │   ├── ecr/                        # Container registry
│   │   └── ecs/                        # Container orchestration
│   │
│   └── scripts/
│       ├── jenkins-setup.sh            # Jenkins installation
│       └── app-server-setup.sh         # App server setup
│
└── .amazonq/                           # Amazon Q context
    └── rules/
        └── memory-bank/
            ├── product.md              # Product overview
            ├── structure.md            # Project structure
            └── tech.md                 # Technology details
```

---

## Prerequisites

### Required Software
- **AWS CLI**: Configured with credentials (`aws configure`)
- **Terraform**: >= 1.0
- **Git**: For version control
- **SSH Client**: For server access

### Required Accounts
- **AWS Account**: With administrative access
- **Docker Hub Account**: For container registry (optional if using ECR)
- **GitHub Account**: For source code repository
- **SonarQube Account**: For code quality analysis (optional)
- **Snyk Account**: For dependency scanning (optional)

### Required Information
- **Your Public IP**: Run `curl ifconfig.me`
- **AWS Region**: Default is `eu-central-1`
- **SSH Key Pair**: Will be auto-generated by Terraform

### System Requirements
- **Local Machine**: Any OS with Terraform and AWS CLI
- **Jenkins Server**: t3.medium (2 vCPU, 4GB RAM) recommended
- **App Server**: t3.small (2 vCPU, 2GB RAM) minimum

---

## Quick Start Guide

### 1. Clone Repository
```bash
git clone https://github.com/your-username/Gitops.git
cd Gitops
```

### 2. Configure Terraform
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
cat > terraform.tfvars << EOF
aws_region              = "eu-central-1"
project_name            = "jenkins-cicd-pipeline"
environment             = "dev"
allowed_ips             = ["$(curl -s ifconfig.me)/32"]
jenkins_instance_type   = "t3.medium"
app_instance_type       = "t3.small"
jenkins_admin_password  = "YourSecurePassword123!"
EOF
```

### 3. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply -auto-approve

# Save outputs
terraform output > ../infrastructure-outputs.txt
```

### 4. Access Jenkins
```bash
# Get Jenkins URL
JENKINS_IP=$(terraform output -raw jenkins_public_ip)
echo "Jenkins URL: http://$JENKINS_IP:8080"

# Get initial password
ssh -i jenkins-cicd-pipeline-dev-keypair.pem ec2-user@$JENKINS_IP \
  "sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
```

### 5. Configure Jenkins
1. Open Jenkins URL in browser
2. Enter initial admin password
3. Install suggested plugins
4. Create admin user
5. Install additional plugins: Docker Pipeline, SSH Agent, NodeJS
6. Configure NodeJS tool: `nodejs-20`

### 6. Add Credentials
- **registry_creds**: Docker Hub username/password
- **ec2_ssh**: SSH private key for EC2 access
- **snyk-token**: Snyk API token (optional)

### 7. Create Pipeline
1. New Item → Pipeline
2. Pipeline script from SCM → Git
3. Repository URL: Your GitHub repo
4. Branch: `*/main`
5. Script Path: `Jenkinsfile`

### 8. Run Pipeline
Click "Build Now" and monitor console output.

### 9. Verify Deployment
```bash
# Get ECS service URL or EC2 IP
curl http://YOUR_APP_URL:5000/health
```

---

## Detailed Setup Instructions

See [SETUP-GUIDE.md](SETUP-GUIDE.md) for comprehensive step-by-step instructions.

---

## Pipeline Variants

### 1. Jenkinsfile (Default - Warn-Only Mode)
- **Location**: `Jenkinsfile`
- **Behavior**: Security findings mark build UNSTABLE but never block deployment
- **Use Case**: Development environments, rapid iteration
- **Quality Gates**: All wrapped in `catchError(buildResult: 'UNSTABLE')`

### 2. Jenkinsfile-strict (Fail-Fast Mode)
- **Location**: `Jenkinsfile-strict`
- **Behavior**: Any HIGH/CRITICAL finding immediately fails the build
- **Use Case**: Production environments, compliance requirements
- **Quality Gates**: Calls `error()` on any security finding

### 3. Jenkinsfile-warn-only (Explicit Warn-Only)
- **Location**: `Jenkinsfile-warn-only`
- **Behavior**: Identical to default Jenkinsfile
- **Use Case**: Backup/reference implementation

### 4. Jenkinsfile.ec2 (EC2 Deployment)
- **Location**: `Jenkinsfile.ec2`
- **Behavior**: Deploys to EC2 via SSH instead of ECS
- **Use Case**: Simple deployments without container orchestration

### Switching Between Modes

```bash
# Use strict mode
cp Jenkinsfile-strict Jenkinsfile
git add Jenkinsfile
git commit -m "Switch to strict security mode"
git push

# Use warn-only mode
cp Jenkinsfile-warn-only Jenkinsfile
git add Jenkinsfile
git commit -m "Switch to warn-only mode"
git push
```

---

## Security Features

### Secret Scanning (Gitleaks)
- **Tool**: Gitleaks
- **Stage**: 2
- **Detects**: AWS keys, API tokens, passwords in code
- **Configuration**: `.gitleaks.toml`
- **Report**: `gitleaks-report.json`

### Static Application Security Testing (SAST)
- **Tool**: SonarQube
- **Stage**: 4
- **Detects**: Code smells, bugs, security vulnerabilities
- **Configuration**: `sonar-project.properties`
- **Quality Gate**: Configurable pass/fail criteria

### Software Composition Analysis (SCA)
- **Tools**: npm audit + Snyk
- **Stage**: 5
- **Detects**: Vulnerable dependencies
- **Reports**: `npm-audit-report.json`, `snyk-report.json`
- **Threshold**: HIGH and CRITICAL severities

### Container Image Scanning
- **Tool**: Trivy
- **Stage**: 9
- **Detects**: OS and library vulnerabilities
- **Configuration**: `trivy.yaml`
- **Report**: `trivy-report.json`

### SBOM Generation
- **Tool**: Syft
- **Stage**: 8
- **Formats**: CycloneDX JSON, SPDX JSON
- **Artifacts**: `sbom-cyclonedx.json`, `sbom-spdx.json`

### Security Best Practices
- IP whitelisting via `allowed_ips` variable
- Auto-generated SSH keys (never committed)
- Secrets stored in Jenkins credentials
- Security groups with minimal required access
- Container scanning before deployment
- Encrypted data at rest and in transit

---

## Operations Guide

### Daily Operations

#### Check Pipeline Status
```bash
# Jenkins UI
http://JENKINS_IP:8080/job/cicd-pipeline/

# CLI (requires Jenkins CLI)
java -jar jenkins-cli.jar -s http://JENKINS_IP:8080/ \
  -auth admin:password get-job cicd-pipeline
```

#### Monitor Application
```bash
# Health check
curl http://APP_URL:5000/health

# Application info
curl http://APP_URL:5000/api/info

# Container logs (EC2)
ssh -i keypair.pem ec2-user@APP_IP "docker logs node-app -f"

# ECS logs
aws logs tail /ecs/jenkins-cicd-pipeline-task --follow
```

#### View Security Reports
```bash
# Download from Jenkins
http://JENKINS_IP:8080/job/cicd-pipeline/lastBuild/artifact/

# Reports available:
# - gitleaks-report.json
# - npm-audit-report.json
# - snyk-report.json
# - trivy-report.json
# - sbom-cyclonedx.json
# - sbom-spdx.json
```

### Deployment Procedures

#### Standard Deployment
```bash
# 1. Make code changes
vim app.js

# 2. Test locally
npm test

# 3. Commit and push
git add .
git commit -m "feat: add new feature"
git push origin main

# 4. Pipeline triggers automatically (if webhook configured)
# Or manually: Jenkins → Build Now
```

#### Emergency Rollback
```bash
# EC2 Deployment
ssh -i keypair.pem ec2-user@APP_IP
docker stop node-app && docker rm node-app
docker run -d --name node-app -p 5000:5000 \
  YOUR_REGISTRY/cicd-app:PREVIOUS_BUILD_NUMBER

# ECS Deployment
aws ecs update-service \
  --cluster jenkins-cicd-pipeline-cluster \
  --service jenkins-cicd-pipeline-service \
  --task-definition jenkins-cicd-pipeline-task:PREVIOUS_REVISION
```

#### Blue-Green Deployment
See [RUNBOOK.md](RUNBOOK.md) for detailed blue-green deployment procedures.

### Maintenance Tasks

#### Update Jenkins Plugins
```bash
# SSH to Jenkins server
ssh -i keypair.pem ec2-user@JENKINS_IP

# Update plugins
sudo docker exec jenkins bash -c \
  "java -jar /usr/share/jenkins/jenkins-cli.jar -s http://localhost:8080/ \
  -auth admin:password install-plugin PLUGIN_NAME"

# Restart Jenkins
sudo docker restart jenkins
```

#### Clean Up Old Images
```bash
# ECR cleanup (automated in pipeline stage 15)
aws ecr list-images --repository-name jenkins-cicd-pipeline-app

# Manual cleanup
aws ecr batch-delete-image \
  --repository-name jenkins-cicd-pipeline-app \
  --image-ids imageTag=OLD_TAG
```

#### Rotate Credentials
```bash
# 1. Generate new Docker Hub token
# 2. Update Jenkins credential: registry_creds
# 3. Generate new SSH key
cd terraform
terraform taint module.keypair.tls_private_key.this
terraform apply
# 4. Update Jenkins credential: ec2_ssh
```

---

## Troubleshooting

### Common Issues

#### 1. Terraform Apply Fails
**Symptom**: `Error: Error creating VPC` or similar

**Solutions**:
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check region
aws configure get region

# Verify allowed_ips is set
grep allowed_ips terraform.tfvars

# Check for resource limits
aws service-quotas list-service-quotas \
  --service-code ec2 --query 'Quotas[?QuotaName==`Running On-Demand Standard instances`]'
```

#### 2. Jenkins Not Accessible
**Symptom**: Cannot reach `http://JENKINS_IP:8080`

**Solutions**:
```bash
# Check EC2 instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*"

# Check security group
aws ec2 describe-security-groups --group-names "*jenkins*"

# SSH and check Docker
ssh -i keypair.pem ec2-user@JENKINS_IP
sudo docker ps
sudo docker logs jenkins

# Check setup log
sudo cat /var/log/jenkins-setup.log
```

#### 3. Pipeline Fails at Docker Build
**Symptom**: `docker: command not found` or `permission denied`

**Solutions**:
```bash
# Check Docker in Jenkins container
ssh -i keypair.pem ec2-user@JENKINS_IP
sudo docker exec jenkins docker --version

# Check Docker socket mount
sudo docker inspect jenkins | grep -A 5 Mounts

# Restart Jenkins container
sudo docker restart jenkins
```

#### 4. ECS Deployment Fails
**Symptom**: `Service failed to stabilize`

**Solutions**:
```bash
# Check ECS service events
aws ecs describe-services \
  --cluster jenkins-cicd-pipeline-cluster \
  --services jenkins-cicd-pipeline-service

# Check task logs
aws logs tail /ecs/jenkins-cicd-pipeline-task --follow

# Check task definition
aws ecs describe-task-definition \
  --task-definition jenkins-cicd-pipeline-task

# Verify ECR image exists
aws ecr describe-images \
  --repository-name jenkins-cicd-pipeline-app
```

#### 5. Security Scan Failures
**Symptom**: Pipeline marked UNSTABLE or FAILED

**Solutions**:
```bash
# Review Gitleaks report
cat gitleaks-report.json | jq '.[] | {file, line, secret}'

# Review npm audit
npm audit --json | jq '.vulnerabilities'

# Review Trivy report
cat trivy-report.json | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL")'

# Fix vulnerabilities
npm audit fix
npm update

# Rebuild and retest
docker build -t test .
docker run --rm aquasec/trivy:latest image test
```

### Debug Commands

```bash
# Jenkins container shell
sudo docker exec -it jenkins bash

# Check Jenkins logs
sudo docker logs jenkins --tail 100 -f

# Check disk space
df -h

# Check memory
free -m

# Check Docker images
docker images

# Check Docker containers
docker ps -a

# Check network connectivity
curl -I https://registry.hub.docker.com/

# Test AWS credentials
aws sts get-caller-identity

# Test ECR login
aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin \
  962496666337.dkr.ecr.eu-central-1.amazonaws.com
```

---

## Cost Analysis

### Monthly AWS Costs (eu-central-1)

| Resource | Type | Hours/Month | Cost/Hour | Monthly Cost |
|----------|------|-------------|-----------|--------------|
| Jenkins EC2 | t3.medium | 730 | $0.0416 | $30.37 |
| App EC2 | t3.small | 730 | $0.0208 | $15.18 |
| ECS Fargate | 0.25 vCPU, 0.5GB | 730 | $0.0138 | $10.07 |
| ECR Storage | 10 GB | - | $0.10/GB | $1.00 |
| Data Transfer | 50 GB | - | $0.09/GB | $4.50 |
| **Total** | | | | **~$61/month** |

### Cost Optimization Tips

1. **Stop instances when not in use**:
```bash
# Stop EC2 instances
aws ec2 stop-instances --instance-ids i-xxxxx i-yyyyy

# Start when needed
aws ec2 start-instances --instance-ids i-xxxxx i-yyyyy
```

2. **Use Spot Instances** (for non-production):
```hcl
# In terraform/modules/jenkins/main.tf
resource "aws_instance" "jenkins" {
  instance_market_options {
    market_type = "spot"
  }
}
```

3. **Enable ECR Lifecycle Policy**:
```bash
aws ecr put-lifecycle-policy \
  --repository-name jenkins-cicd-pipeline-app \
  --lifecycle-policy-text file://ecr-lifecycle-policy.json
```

4. **Use ECS Fargate Spot**:
```hcl
capacity_provider_strategy {
  capacity_provider = "FARGATE_SPOT"
  weight            = 1
}
```

---

## Maintenance

### Weekly Tasks
- [ ] Review security scan reports
- [ ] Check for failed builds
- [ ] Monitor disk space on Jenkins server
- [ ] Review CloudWatch alarms

### Monthly Tasks
- [ ] Update Jenkins plugins
- [ ] Update Docker base images
- [ ] Review and update dependencies (`npm update`)
- [ ] Rotate credentials
- [ ] Review AWS costs

### Quarterly Tasks
- [ ] Update Terraform providers
- [ ] Review and update security policies
- [ ] Audit IAM roles and permissions
- [ ] Review and optimize infrastructure costs
- [ ] Update documentation

### Backup Procedures

```bash
# Backup Jenkins configuration
ssh -i keypair.pem ec2-user@JENKINS_IP
sudo docker exec jenkins tar czf /tmp/jenkins-backup.tar.gz \
  /var/jenkins_home/jobs \
  /var/jenkins_home/credentials.xml \
  /var/jenkins_home/config.xml

# Download backup
scp -i keypair.pem ec2-user@JENKINS_IP:/tmp/jenkins-backup.tar.gz .

# Backup Terraform state
cd terraform
terraform state pull > terraform.tfstate.backup
```

---

## Additional Resources

- [SETUP-GUIDE.md](SETUP-GUIDE.md) - Detailed setup instructions
- [RUNBOOK.md](RUNBOOK.md) - Day-to-day operations
- [GITOPS-RUNBOOK.md](GITOPS-RUNBOOK.md) - GitOps workflow
- [ECS-COMPLETE-RUNBOOK.md](ECS-COMPLETE-RUNBOOK.md) - ECS deployment guide
- [README.md](README.md) - Quick reference

---

## Support & Contributing

### Getting Help
1. Check troubleshooting section above
2. Review Jenkins console output
3. Check AWS CloudWatch logs
4. Review security scan reports

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

**Last Updated**: 2024
**Version**: 1.0.0
**Maintainer**: Your Name
