# terraform/modules/cloudwatch/outputs.tf

output "alarm_arn"  { value = aws_cloudwatch_metric_alarm.error_warn.arn }
output "alarm_name" { value = aws_cloudwatch_metric_alarm.error_warn.alarm_name }
output "metric_filter_name" { value = aws_cloudwatch_log_metric_filter.error_warn.name }
