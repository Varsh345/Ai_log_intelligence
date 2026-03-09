# terraform/modules/lambda/outputs.tf

output "lambda_arn"  { value = aws_lambda_function.analyzer.arn }
output "lambda_name" { value = aws_lambda_function.analyzer.function_name }
output "idempotency_table_name" { value = aws_dynamodb_table.idempotency.name }
