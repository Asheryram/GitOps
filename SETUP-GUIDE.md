# Complete CI/CD Pipeline Setup Guide

## 🎯 Overview

This guide walks you through setting up a complete CI/CD pipeline from scratch, including:
- AWS infrastructure provisioning with Terraform
- Jenkins CI/CD server configuration
- Node.js application deployment
- Docker containerization and registry

**Total Setup Time**: ~20-30 minutes

## 📋 Prerequisites Checklist

Before starting, ensure you have:

- [ ] **AWS Account** with administrative access
- [ ] **AWS CLI** configured with credentials
- [ ] **Terraform** >= 1.0 installed locally
- [ ] **Docker Hub** account created
- [ ] **Git repository** (GitHub/GitLab) with this code
- [ ] **SSH Key Pair** created in AWS EC2
- [ ] **Your public IP** address (for security groups)

### Quick Prerequisites Setup

```bash
# Install AWS CLI (if not installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS CLI
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)

# Install Terraform (if not installed)
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify installations
aws --version
terraform --version

# Get your public IP
curl ifconfig.me
```

## 🚀 Step-by-Step Setup

### Phase 1: Infrastructure Deployment (10 minutes)

#### 1.1 Clone and Prepare Repository

```bash
# Clone your repository
git clone https://github.com/your-username/Project_Complete_CICD_Pipeline_Jenkins.git
cd Project_Complete_CICD_Pipeline_Jenkins

# Navigate to Terraform directory
cd terraform
```

#### 1.2 Create Terraform Variables File

```bash
# Create terraform.tfvars with your specific values
cat > terraform.tfvars << EOF
aws_region = "us-east-1"
project_name = "cicd-pipeline"
environment = "dev"
jenkins_admin_password = "SecurePassword123!"
allowed_ips = ["$(curl -s ifconfig.me)/32"]
jenkins_instance_type = "t3.medium"
app_instance_type = "t3.small"
EOF

# Verify the file
cat terraform.tfvars
```

#### 1.3 Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment (review what will be created)
terraform plan

# Apply infrastructure (type 'yes' when prompted)
terraform apply

# Save outputs to file for reference
terraform output > ../infrastructure-outputs.txt
```

**Expected Infrastructure Created:**
- VPC with public/private subnets
- Security groups for Jenkins and App servers
- Jenkins EC2 instance (t3.medium)
- Application EC2 instance (t3.small)
- Internet Gateway and Route Tables

#### 1.4 Record Important Information

```bash
# Display and record these values
terraform output jenkins_url
terraform output app_url
terraform output ssh_jenkins
terraform output ssh_app_server

# Example outputs:
# jenkins_url = "http://3.15.123.45:8080"
# app_url = "http://3.15.123.67:5000"
```

### Phase 2: Jenkins Configuration (8 minutes)

#### 2.1 Wait for Jenkins Startup

```bash
# Jenkins takes 2-3 minutes to fully start after EC2 launch
# Check if Jenkins is ready
JENKINS_IP=$(terraform output -raw jenkins_public_ip)
curl -I http://$JENKINS_IP:8080

# Wait until you get HTTP 200 or 403 response
```

#### 2.2 Get Jenkins Initial Password

```bash
# SSH into Jenkins server
ssh -i ~/.ssh/your-key-pair.pem ec2-user@$JENKINS_IP

# Get initial admin password (Jenkins runs in Docker)
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# Copy this password and exit
exit
```

#### 2.3 Complete Jenkins Setup

1. **Open Jenkins in browser**: `http://JENKINS_IP:8080`
2. **Unlock Jenkins**: Paste the initial admin password
3. **Install Plugins**: Click "Install suggested plugins"
4. **Create Admin User**:
   - Username: `admin`
   - Password: Use the one from terraform.tfvars
   - Full name: `CI/CD Admin`
   - Email: `your-email@example.com`
5. **Instance Configuration**: Keep default Jenkins URL
6. **Start Using Jenkins**

#### 2.4 Configure Jenkins Credentials

**Navigate to**: Jenkins → Manage Jenkins → Credentials → System → Global credentials (unrestricted)

**Add Credential #1 - Docker Hub**:
- Kind: `Username with password`
- Scope: `Global`
- Username: `your-dockerhub-username`
- Password: `your-dockerhub-password-or-token`
- ID: `registry_creds`
- Description: `Docker Hub Credentials`

**Add Credential #2 - EC2 SSH Key**:
- Kind: `SSH Username with private key`
- Scope: `Global`
- ID: `ec2_ssh`
- Description: `EC2 SSH Key`
- Username: `ec2-user`
- Private Key: `Enter directly` → Paste your private key content
- Passphrase: Leave empty (if no passphrase)

### Phase 3: Pipeline Setup (5 minutes)

#### 3.1 Create Jenkins Pipeline

1. **Jenkins Dashboard** → **New Item**
2. **Item name**: `CICD-Node-Pipeline`
3. **Type**: Select `Pipeline` → **OK**

#### 3.2 Configure Pipeline

**General Section**:
- Description: `Complete CI/CD Pipeline for Node.js Application`

**Pipeline Section**:
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: `https://github.com/your-username/Project_Complete_CICD_Pipeline_Jenkins.git`
- Credentials: Leave as `- none -` (for public repos)
- Branch Specifier: `*/main`
- Script Path: `Jenkinsfile`

**Save** the configuration

#### 3.3 Update Jenkinsfile with EC2 IP

```bash
# Back in your local terminal, get app server IP
cd terraform
APP_IP=$(terraform output -raw app_server_public_ip)
echo "App Server IP: $APP_IP"

# Update Jenkinsfile
cd ..
sed -i "s/YOUR_EC2_PUBLIC_IP_HERE/$APP_IP/g" Jenkinsfile

# Verify the change
grep "EC2_HOST" Jenkinsfile

# Commit and push the change
git add Jenkinsfile
git commit -m "Update EC2_HOST with actual IP address"
git push origin main
```

### Phase 4: First Deployment (5 minutes)

#### 4.1 Run the Pipeline

1. **Jenkins Dashboard** → **CICD-Node-Pipeline**
2. **Build Now**
3. **Monitor Progress**: Click on build number → **Console Output**

**Expected Pipeline Flow**:
```
Started by user admin
Checking out code from repository...
Installing dependencies...
Running unit tests...
Building Docker image...
Pushing image to registry...
Deploying to EC2...
Finished: SUCCESS
```

#### 4.2 Verify Deployment

```bash
# Test application endpoints
APP_IP=$(cd terraform && terraform output -raw app_server_public_ip)

# Test main page
curl http://$APP_IP:5000/

# Test health endpoint
curl http://$APP_IP:5000/health

# Test API endpoint
curl http://$APP_IP:5000/api/info

# Open in browser
echo "Open in browser: http://$APP_IP:5000/"
```

**Expected Responses**:
- Main page: HTML with deployment info
- Health: `{"status":"healthy"}`
- API Info: `{"version":"1.0.0","deploymentTime":"...","status":"running"}`

## ✅ Verification Checklist

After successful setup, verify:

- [ ] **Infrastructure**: All AWS resources created
- [ ] **Jenkins**: Accessible and configured
- [ ] **Pipeline**: Runs successfully
- [ ] **Application**: Responds on all endpoints
- [ ] **Docker**: Container running on EC2
- [ ] **Security**: Only your IP can SSH

### Detailed Verification Commands

```bash
# Check Terraform state
cd terraform
terraform state list

# Check Jenkins status
curl -I http://$(terraform output -raw jenkins_public_ip):8080

# Check application status
APP_IP=$(terraform output -raw app_server_public_ip)
curl -I http://$APP_IP:5000

# SSH into app server and check Docker
ssh -i ~/.ssh/your-key.pem ec2-user@$APP_IP
docker ps
docker logs node-app
exit
```

## 🔧 Post-Setup Configuration

### Enable Blue Ocean (Optional)

1. **Manage Jenkins** → **Manage Plugins**
2. **Available** tab → Search "Blue Ocean"
3. **Install** Blue Ocean plugin
4. **Restart Jenkins**
5. Access via **Open Blue Ocean** link

### Set up Webhooks (Optional)

For automatic builds on git push:

1. **GitHub Repository** → **Settings** → **Webhooks**
2. **Add webhook**:
   - Payload URL: `http://JENKINS_IP:8080/github-webhook/`
   - Content type: `application/json`
   - Events: `Just the push event`

## 🚨 Troubleshooting Common Issues

### Issue 1: Terraform Apply Fails

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check if key pair exists
aws ec2 describe-key-pairs --key-names your-key-name

# Verify region
aws configure get region
```

### Issue 2: Jenkins Not Accessible

```bash
# Check security group
aws ec2 describe-security-groups --group-names "*jenkins*"

# Check EC2 instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*"

# SSH into Jenkins server and check service
ssh -i ~/.ssh/your-key.pem ec2-user@JENKINS_IP
sudo systemctl status jenkins
sudo journalctl -u jenkins -f
```

### Issue 3: Pipeline Fails at Docker Push

```bash
# Test Docker Hub login manually
docker login -u your-username

# Check credentials in Jenkins
# Manage Jenkins → Credentials → registry_creds
```

### Issue 4: Cannot SSH to EC2

```bash
# Check key permissions
chmod 400 ~/.ssh/your-key.pem

# Test SSH connection
ssh -v -i ~/.ssh/your-key.pem ec2-user@EC2_IP

# Check security group allows SSH from your IP
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
```

## 🧹 Cleanup Instructions

### Complete Cleanup

```bash
# Destroy all infrastructure
cd terraform
terraform destroy

# Confirm with 'yes'

# Clean up local files
cd ..
rm -f infrastructure-outputs.txt
```

### Partial Cleanup (Keep Infrastructure)

```bash
# SSH to app server and clean containers
ssh -i ~/.ssh/your-key.pem ec2-user@$APP_IP
docker stop node-app
docker rm node-app
docker system prune -af
exit

# Clean Jenkins workspace
# Jenkins → Manage Jenkins → Manage Nodes → Built-in Node → Configure
# Set workspace cleanup policy
```

## 📊 Cost Estimation

**Monthly AWS Costs** (us-east-1):
- t3.medium (Jenkins): ~$30/month
- t3.small (App): ~$15/month
- VPC, Security Groups: Free
- Data Transfer: ~$1-5/month

**Total**: ~$46-50/month

## 🎉 Success Indicators

You've successfully completed the setup when:

1. ✅ Terraform shows all resources created
2. ✅ Jenkins is accessible and configured
3. ✅ Pipeline runs without errors
4. ✅ Application responds on all endpoints
5. ✅ Docker container is running on EC2
6. ✅ You can make code changes and see them deployed

## 📞 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review Jenkins console output
3. Check AWS CloudWatch logs
4. Verify all prerequisites are met
5. Ensure all IPs and credentials are correct

**Common Support Resources**:
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EC2 Troubleshooting](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-troubleshoot.html)

---

**🎯 Next Steps**: Once setup is complete, try making changes to `app.js` and push to see the automatic deployment in action!