terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}





provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}


# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
}

# Key Pair Module
module "keypair" {
  source = "./modules/keypair"

  project_name = var.project_name
  environment  = var.environment
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  allowed_ips  = var.allowed_ips
}

# Jenkins EC2 Module
module "jenkins" {
  source = "./modules/jenkins"

  project_name           = var.project_name
  environment            = var.environment
  ami_id                 = data.aws_ami.amazon_linux.id
  instance_type          = var.jenkins_instance_type
  key_name               = module.keypair.key_name
  subnet_id              = module.vpc.public_subnets[0]
  security_group_ids     = [module.security_groups.jenkins_sg_id]
  jenkins_admin_password = var.jenkins_admin_password
  aws_region             = var.aws_region
}

# Application EC2 Module
module "app_server" {
  source = "./modules/ec2"

  project_name       = var.project_name
  environment        = var.environment
  ami_id             = data.aws_ami.amazon_linux.id
  instance_type      = var.app_instance_type
  key_name           = module.keypair.key_name
  subnet_id          = module.vpc.public_subnets[1]
  security_group_ids = [module.security_groups.app_sg_id]
  user_data          = file("${path.module}/scripts/app-server-setup.sh")
}
