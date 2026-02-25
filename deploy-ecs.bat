@echo off
echo 🚀 Deploying ECS Infrastructure...

REM Navigate to terraform directory
cd terraform

REM Initialize and apply Terraform
echo 📋 Initializing Terraform...
terraform init

echo 📋 Planning Terraform deployment...
terraform plan

echo 🏗️ Applying Terraform configuration...
terraform apply -auto-approve

if %errorlevel% equ 0 (
    echo ✅ ECS infrastructure deployed successfully!
    
    REM Get outputs
    echo 📊 Infrastructure Details:
    for /f "delims=" %%i in ('terraform output -raw ecs_cluster_name') do echo ECS Cluster: %%i
    for /f "delims=" %%i in ('terraform output -raw ecs_service_name') do echo ECS Service: %%i
    for /f "delims=" %%i in ('terraform output -raw ecs_task_definition_family') do echo Task Family: %%i
    for /f "delims=" %%i in ('terraform output -raw ecr_repository_url') do echo ECR Repository: %%i
    
    echo.
    echo 🔄 Next Steps:
    echo 1. Rename Jenkinsfile.ecs to Jenkinsfile to use the ECS pipeline
    echo 2. Update Jenkins pipeline to use the new Jenkinsfile
    echo 3. Run your pipeline to deploy the application to ECS
    
) else (
    echo ❌ Terraform deployment failed!
    exit /b 1
)