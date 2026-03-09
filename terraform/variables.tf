# terraform/variables.tf

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "ai-log-intelligence"
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type        = string
  default     = "prod"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_id" {
  description = "VPC ID where EC2 will be launched"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for the EC2 instance"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 (e.g. your IP/32)"
  type        = string
  default     = "0.0.0.0/0"
}

# ── CloudWatch / Logging ──────────────────────────────────────────────────────
variable "log_group_name" {
  description = "CloudWatch Log Group name for application logs"
  type        = string
  default     = "/aws/ec2/ai-log-intelligence/app"
}

variable "log_retention_days" {
  description = "CloudWatch Log Group retention in days"
  type        = number
  default     = 14
}

variable "metric_namespace" {
  description = "CloudWatch custom metric namespace"
  type        = string
  default     = "AILogIntelligence"
}

variable "error_count_threshold" {
  description = "Number of ERROR/WARN events to trigger the alarm"
  type        = number
  default     = 1
}

variable "alarm_period" {
  description = "CloudWatch alarm evaluation period in seconds"
  type        = number
  default     = 60
}

# ── SNS ───────────────────────────────────────────────────────────────────────
variable "sns_topic_name" {
  description = "Name for the SNS alerts topic (do not change after first apply)"
  type        = string
  default     = "ai-log-intelligence-prod-alerts"
}

# ── EC2 ───────────────────────────────────────────────────────────────────────
variable "ec2_instance_type" {
  description = "EC2 instance type for the Ollama host"
  type        = string
  default     = "m6i.xlarge"
}

variable "ec2_root_volume_size" {
  description = "EC2 root EBS volume size in GiB"
  type        = number
  default     = 40
}

# ── Lambda ────────────────────────────────────────────────────────────────────
variable "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 120
}

variable "lambda_memory_mb" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}
