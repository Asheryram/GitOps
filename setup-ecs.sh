#!/bin/bash

# ECS Service Creation Script
# Run this after terraform apply to create the ECS service

set -e

echo "🚀 Creating ECS Service..."

# Get Terraform outputs
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
TASK_EXECUTION_ROLE=$(terraform output -raw ecs_task_execution_role_arn)
TASK_ROLE=$(terraform output -raw ecs_task_role_arn)
LOG_GROUP=$(terraform output -raw ecs_log_group_name)
SECURITY_GROUP=$(terraform output -raw ecs_service_security_group_id)
SUBNETS=$(terraform output -json public_subnets | jq -r '.[]' | tr '\n' ',' | sed 's/,$//')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"

echo "Cluster: $CLUSTER_NAME"
echo "ECR Repo: $ECR_REPO_URL"
echo "Subnets: $SUBNETS"

# Create initial task definition
cat > ecs-task-definition-resolved.json << EOF
{
  "family": "cicd-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$TASK_EXECUTION_ROLE",
  "taskRoleArn": "$TASK_ROLE",
  "containerDefinitions": [
    {
      "name": "cicd-node-app",
      "image": "$ECR_REPO_URL:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 5000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "PORT",
          "value": "5000"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Build and push initial image
echo "📦 Building and pushing initial image..."
docker build -t cicd-node-app:latest .
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URL
docker tag cicd-node-app:latest $ECR_REPO_URL:latest
docker push $ECR_REPO_URL:latest

# Register task definition
echo "📋 Registering task definition..."
aws ecs register-task-definition --cli-input-json file://ecs-task-definition-resolved.json

# Create ECS service
echo "🎯 Creating ECS service..."
aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name cicd-service \
    --task-definition cicd-task:1 \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUP],assignPublicIp=ENABLED}"

echo "⏳ Waiting for service to stabilize..."
aws ecs wait services-stable --cluster $CLUSTER_NAME --services cicd-service

echo "✅ ECS Service created successfully!"
echo "🔍 Service status:"
aws ecs describe-services --cluster $CLUSTER_NAME --services cicd-service --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# Get task public IP for testing
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name cicd-service --query 'taskArns[0]' --output text)
if [ "$TASK_ARN" != "None" ]; then
    ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
    PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
    echo "🌐 Application URL: http://$PUBLIC_IP:5000"
    echo "❤️  Health check: http://$PUBLIC_IP:5000/health"
fi

echo "🎉 Setup complete! Use Jenkinsfile.ecs for CI/CD pipeline."