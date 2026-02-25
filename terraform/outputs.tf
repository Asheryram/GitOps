output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "jenkins_public_ip" {
  description = "Public IP address of Jenkins server"
  value       = module.jenkins.public_ip
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${module.jenkins.public_ip}:8080"
}

output "app_server_public_ip" {
  description = "Public IP address of application server"
  value       = module.app_server.public_ip
}

output "app_server_private_ip" {
  description = "Private IP address of application server (for Jenkins deployment)"
  value       = module.app_server.private_ip
}

output "app_url" {
  description = "Application URL"
  value       = "http://${module.app_server.public_ip}:5000"
}

output "ssh_private_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the SSH private key. Retrieve with: aws secretsmanager get-secret-value --secret-id <arn> --query SecretString --output text"
  value       = module.keypair.private_key_secret_arn
}

output "ssh_jenkins" {
  description = "SSH command for Jenkins server (retrieve key from Secrets Manager first)"
  value       = "ssh -i <private-key-file> ec2-user@${module.jenkins.public_ip}"
}

output "ssh_app_server" {
  description = "SSH command for application server (retrieve key from Secrets Manager first)"
  value       = "ssh -i <private-key-file> ec2-user@${module.app_server.public_ip}"
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = module.ecr.repository_name
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.ecs.task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = module.ecs.task_role_arn
}

output "ecs_log_group_name" {
  description = "ECS CloudWatch log group name"
  value       = module.ecs.log_group_name
}

output "ecs_service_security_group_id" {
  description = "ECS service security group ID"
  value       = module.ecs.service_security_group_id
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "ecs_task_definition_family" {
  description = "ECS task definition family"
  value       = module.ecs.task_definition_family
}

output "public_subnets" {
  description = "Public subnet IDs for ECS service"
  value       = module.vpc.public_subnets
}