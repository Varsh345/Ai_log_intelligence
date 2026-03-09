# terraform/outputs.tf

output "ec2_instance_id" {
  description = "ID of the EC2 instance running Ollama"
  value       = module.ec2.instance_id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance (Ollama host)"
  value       = module.ec2.public_ip
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = module.sns.topic_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda.lambda_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = module.lambda.lambda_arn
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm"
  value       = module.cloudwatch.alarm_arn
}

output "idempotency_table_name" {
  description = "DynamoDB table name for Lambda idempotency"
  value       = module.lambda.idempotency_table_name
}

output "ollama_url" {
  description = "Ollama API endpoint used by Lambda"
  value       = "http://${module.ec2.public_ip}:11434/api/generate"
}
