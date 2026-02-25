#!/bin/bash

echo "🚀 Deploying ECS Infrastructure..."

# Navigate to terraform directory
cd terraform

# Initialize and apply Terraform
echo "📋 Initializing Terraform..."
terraform init

echo "📋 Planning Terraform deployment..."
terraform plan

echo "🏗️ Applying Terraform configuration..."
terraform apply -auto-approve

if [ $? -eq 0 ]; then
    echo "✅ ECS infrastructure deployed successfully!"
    
    # Get outputs
    echo "📊 Infrastructure Details:"
    echo "ECS Cluster: $(terraform output -raw ecs_cluster_name)"
    echo "ECS Service: $(terraform output -raw ecs_service_name)"
    echo "Task Family: $(terraform output -raw ecs_task_definition_family)"
    echo "ECR Repository: $(terraform output -raw ecr_repository_url)"
    
    echo ""
    echo "🔄 Next Steps:"
    echo "1. Rename Jenkinsfile.ecs to Jenkinsfile to use the ECS pipeline"
    echo "2. Update Jenkins pipeline to use the new Jenkinsfile"
    echo "3. Run your pipeline to deploy the application to ECS"
    
else
    echo "❌ Terraform deployment failed!"
    exit 1
fi