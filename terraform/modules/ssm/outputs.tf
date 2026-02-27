output "ssm_parameter_path" {
  description = "Base path for Jenkins CI/CD SSM parameters"
  value       = "/jenkins/cicd/"
}

output "parameter_names" {
  description = "List of all SSM parameter names created"
  value = [
    aws_ssm_parameter.aws_region.name,
    aws_ssm_parameter.ecr_repo.name,
    aws_ssm_parameter.ecs_cluster.name,
    aws_ssm_parameter.ecs_service.name,
    aws_ssm_parameter.ecs_task_family.name,
    aws_ssm_parameter.sonar_project.name,
    aws_ssm_parameter.sonar_org.name,
    aws_ssm_parameter.images_to_keep.name
  ]
}