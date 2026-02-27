variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repo_name" {
  description = "ECR repository name"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "ecs_task_family" {
  description = "ECS task definition family"
  type        = string
}

variable "sonar_project" {
  description = "SonarQube project key"
  type        = string
}

variable "sonar_org" {
  description = "SonarQube organization"
  type        = string
}

variable "images_to_keep" {
  description = "Number of ECR images to keep"
  type        = string
}