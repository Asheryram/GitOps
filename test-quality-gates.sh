#!/bin/bash

# Test Quality Gates Script
# This script validates the security scanning and deployment pipeline

set -e

echo "🔍 Testing Security Pipeline Quality Gates"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Secret Detection Test
echo -e "\n${YELLOW}Test 1: Secret Detection${NC}"
echo "Creating test file with fake secret..."

# Create a test file with a fake AWS key
echo "AWS_SECRET_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE" > test-secret.txt
echo "API_KEY=sk-1234567890abcdef" >> test-secret.txt

# Run Gitleaks
echo "Running Gitleaks scan..."
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
    --source /repo \
    --report-path gitleaks-test-report.json \
    --report-format json \
    --no-git || GITLEAKS_EXIT=$?

if [ -f gitleaks-test-report.json ] && [ -s gitleaks-test-report.json ]; then
    SECRET_COUNT=$(jq length gitleaks-test-report.json)
    echo -e "${RED}❌ EXPECTED: Found $SECRET_COUNT secrets${NC}"
    echo "✅ Secret detection working correctly"
else
    echo -e "${GREEN}❌ UNEXPECTED: No secrets detected${NC}"
    echo "⚠️  Secret detection may not be working"
fi

# Cleanup
rm -f test-secret.txt gitleaks-test-report.json

# Test 2: Vulnerable Dependency Test
echo -e "\n${YELLOW}Test 2: Vulnerable Dependency Detection${NC}"
echo "Installing known vulnerable package..."

# Backup current package.json
cp package.json package.json.backup

# Add vulnerable dependency
npm install lodash@4.17.4 --save

echo "Running npm audit..."
npm audit --audit-level=high --json > npm-audit-test.json || NPM_AUDIT_EXIT=$?

if [ "$NPM_AUDIT_EXIT" != "0" ]; then
    VULN_COUNT=$(jq '.metadata.vulnerabilities.high + .metadata.vulnerabilities.critical' npm-audit-test.json)
    echo -e "${RED}❌ EXPECTED: Found $VULN_COUNT high/critical vulnerabilities${NC}"
    echo "✅ Dependency scanning working correctly"
else
    echo -e "${GREEN}❌ UNEXPECTED: No vulnerabilities detected${NC}"
    echo "⚠️  Dependency scanning may not be working"
fi

# Test with Snyk (if token available)
if [ ! -z "$SNYK_TOKEN" ]; then
    echo "Running Snyk scan..."
    npx snyk test --severity-threshold=high --json > snyk-test.json || SNYK_EXIT=$?
    
    if [ "$SNYK_EXIT" != "0" ]; then
        echo -e "${RED}❌ EXPECTED: Snyk found vulnerabilities${NC}"
        echo "✅ Snyk scanning working correctly"
    else
        echo -e "${GREEN}❌ UNEXPECTED: Snyk found no vulnerabilities${NC}"
    fi
fi

# Restore package.json
mv package.json.backup package.json
npm install

# Cleanup
rm -f npm-audit-test.json snyk-test.json

# Test 3: Container Image Vulnerability Test
echo -e "\n${YELLOW}Test 3: Container Image Vulnerability Scanning${NC}"
echo "Building test image with vulnerable base..."

# Create Dockerfile with vulnerable base image
cat > Dockerfile.vulnerable << EOF
FROM node:14.15.0-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 5000
CMD ["npm", "start"]
EOF

# Build vulnerable image
docker build -f Dockerfile.vulnerable -t test-vulnerable-app .

echo "Running Trivy scan on vulnerable image..."
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image \
    --format json \
    --output trivy-test-report.json \
    test-vulnerable-app

# Check results
if [ -f trivy-test-report.json ]; then
    CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' trivy-test-report.json)
    HIGH_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' trivy-test-report.json)
    
    if [ "$CRITICAL_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ EXPECTED: Found $CRITICAL_COUNT critical and $HIGH_COUNT high vulnerabilities${NC}"
        echo "✅ Container scanning working correctly"
    else
        echo -e "${GREEN}❌ UNEXPECTED: No high/critical vulnerabilities found${NC}"
        echo "⚠️  Container scanning may not be sensitive enough"
    fi
fi

# Cleanup
docker rmi test-vulnerable-app || true
rm -f Dockerfile.vulnerable trivy-test-report.json

# Test 4: SBOM Generation Test
echo -e "\n${YELLOW}Test 4: SBOM Generation${NC}"
echo "Building current application image..."

docker build -t test-sbom-app .

echo "Generating SBOM with Syft..."
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/syft:latest test-sbom-app \
    -o cyclonedx-json > test-sbom.json

if [ -f test-sbom.json ] && [ -s test-sbom.json ]; then
    COMPONENT_COUNT=$(jq '.components | length' test-sbom.json)
    echo -e "${GREEN}✅ SBOM generated successfully with $COMPONENT_COUNT components${NC}"
else
    echo -e "${RED}❌ SBOM generation failed${NC}"
fi

# Cleanup
docker rmi test-sbom-app || true
rm -f test-sbom.json

# Test 5: ECS Deployment Validation (if AWS credentials available)
echo -e "\n${YELLOW}Test 5: ECS Deployment Validation${NC}"

if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
    echo "Checking ECS cluster status..."
    
    if aws ecs describe-clusters --clusters cicd-cluster &> /dev/null; then
        CLUSTER_STATUS=$(aws ecs describe-clusters --clusters cicd-cluster --query 'clusters[0].status' --output text)
        echo "ECS Cluster Status: $CLUSTER_STATUS"
        
        if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
            echo -e "${GREEN}✅ ECS cluster is active${NC}"
            
            # Check service if it exists
            if aws ecs describe-services --cluster cicd-cluster --services cicd-service &> /dev/null; then
                SERVICE_STATUS=$(aws ecs describe-services --cluster cicd-cluster --services cicd-service --query 'services[0].status' --output text)
                RUNNING_COUNT=$(aws ecs describe-services --cluster cicd-cluster --services cicd-service --query 'services[0].runningCount' --output text)
                DESIRED_COUNT=$(aws ecs describe-services --cluster cicd-cluster --services cicd-service --query 'services[0].desiredCount' --output text)
                
                echo "Service Status: $SERVICE_STATUS"
                echo "Running Tasks: $RUNNING_COUNT/$DESIRED_COUNT"
                
                if [ "$SERVICE_STATUS" = "ACTIVE" ] && [ "$RUNNING_COUNT" = "$DESIRED_COUNT" ]; then
                    echo -e "${GREEN}✅ ECS service is healthy${NC}"
                else
                    echo -e "${YELLOW}⚠️  ECS service may have issues${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️  ECS service not found (may not be deployed yet)${NC}"
            fi
        else
            echo -e "${RED}❌ ECS cluster is not active${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  ECS cluster not found (may not be created yet)${NC}"
    fi
    
    # Check ECR repository
    if aws ecr describe-repositories --repository-names cicd-node-app &> /dev/null; then
        IMAGE_COUNT=$(aws ecr list-images --repository-name cicd-node-app --query 'imageIds | length(@)')
        echo -e "${GREEN}✅ ECR repository exists with $IMAGE_COUNT images${NC}"
    else
        echo -e "${YELLOW}⚠️  ECR repository not found${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  AWS CLI not configured - skipping ECS validation${NC}"
fi

# Summary
echo -e "\n${YELLOW}=========================================="
echo "🏁 Security Pipeline Test Summary"
echo -e "==========================================${NC}"

echo "✅ Secret detection test completed"
echo "✅ Dependency vulnerability test completed"
echo "✅ Container vulnerability test completed"
echo "✅ SBOM generation test completed"
echo "✅ ECS deployment validation completed"

echo -e "\n${GREEN}🎉 All security pipeline tests completed!${NC}"
echo -e "${YELLOW}💡 Run this script before deploying to validate your security setup${NC}"

# Instructions for fixing issues
echo -e "\n${YELLOW}🔧 If any tests failed:${NC}"
echo "1. Secret detection issues: Check Gitleaks configuration"
echo "2. Dependency issues: Update npm audit or Snyk configuration"
echo "3. Container issues: Update Trivy configuration or base images"
echo "4. SBOM issues: Check Syft installation and Docker access"
echo "5. ECS issues: Verify AWS credentials and infrastructure setup"