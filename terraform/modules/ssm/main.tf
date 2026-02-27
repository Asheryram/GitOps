# SSM Parameter Store parameters for Jenkins CI/CD
resource "aws_ssm_parameter" "aws_region" {
  name  = "/jenkins/cicd/aws-region"
  type  = "String"
  value = var.aws_region

  tags = {
    Name        = "${var.project_name}-${var.environment}-aws-region"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "ecr_repo" {
  name  = "/jenkins/cicd/ecr-repo"
  type  = "String"
  value = var.ecr_repo_name

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecr-repo"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "ecs_cluster" {
  name  = "/jenkins/cicd/ecs-cluster"
  type  = "String"
  value = var.ecs_cluster_name

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-cluster"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "ecs_service" {
  name  = "/jenkins/cicd/ecs-service"
  type  = "String"
  value = var.ecs_service_name

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-service"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "ecs_task_family" {
  name  = "/jenkins/cicd/ecs-task-family"
  type  = "String"
  value = var.ecs_task_family

  tags = {
    Name        = "${var.project_name}-${var.environment}-ecs-task-family"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "sonar_project" {
  name  = "/jenkins/cicd/sonar-project"
  type  = "String"
  value = var.sonar_project

  tags = {
    Name        = "${var.project_name}-${var.environment}-sonar-project"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "sonar_org" {
  name  = "/jenkins/cicd/sonar-org"
  type  = "String"
  value = var.sonar_org

  tags = {
    Name        = "${var.project_name}-${var.environment}-sonar-org"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ssm_parameter" "images_to_keep" {
  name  = "/jenkins/cicd/images-to-keep"
  type  = "String"
  value = var.images_to_keep

  tags = {
    Name        = "${var.project_name}-${var.environment}-images-to-keep"
    Environment = var.environment
    Project     = var.project_name
  }
}