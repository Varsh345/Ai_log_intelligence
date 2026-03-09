# terraform/main.tf
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Data Sources ──────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  name_prefix   = "${var.project_name}-${var.environment}"
  log_group_arn = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# ── Modules ───────────────────────────────────────────────────────────────────
module "sns" {
  source     = "./modules/sns"
  topic_name = var.sns_topic_name
  tags       = local.common_tags
}

module "ec2" {
  source = "./modules/ec2"

  name_prefix           = local.name_prefix
  ami_id                = data.aws_ami.ubuntu.id
  instance_type         = var.ec2_instance_type
  root_volume_size      = var.ec2_root_volume_size
  key_name              = var.ssh_key_name
  vpc_id                = var.vpc_id
  subnet_id             = var.subnet_id
  allowed_ssh_cidr      = var.allowed_ssh_cidr
  log_group_name        = var.log_group_name
  aws_region            = var.aws_region
  tags                  = local.common_tags
}

module "lambda" {
  source = "./modules/lambda"

  name_prefix          = local.name_prefix
  lambda_zip_path      = "${path.module}/modules/lambda/lambda.zip"
  lambda_timeout       = var.lambda_timeout_seconds
  lambda_memory        = var.lambda_memory_mb
  log_group_name       = var.log_group_name
  log_group_arn        = aws_cloudwatch_log_group.app.arn
  sns_topic_arn        = module.sns.topic_arn
  ollama_url           = "http://${module.ec2.public_ip}:11434/api/generate"
  tags                 = local.common_tags

  depends_on = [module.ec2, module.sns]
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  name_prefix           = local.name_prefix
  log_group_name        = var.log_group_name
  metric_namespace      = var.metric_namespace
  error_count_threshold = var.error_count_threshold
  alarm_period          = var.alarm_period
  lambda_arn            = module.lambda.lambda_arn
  lambda_name           = module.lambda.lambda_name
  tags                  = local.common_tags

  depends_on = [module.lambda, aws_cloudwatch_log_group.app]
}
