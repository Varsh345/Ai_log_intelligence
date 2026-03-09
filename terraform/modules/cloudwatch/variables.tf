# terraform/modules/cloudwatch/variables.tf

variable "name_prefix"           { type = string }
variable "log_group_name"        { type = string }
variable "metric_namespace" {
  type    = string
  default = "AILogIntelligence"
}
variable "error_count_threshold" {
  type    = number
  default = 1
}
variable "alarm_period" {
  type    = number
  default = 60
}
variable "lambda_arn"            { type = string }
variable "lambda_name"           { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
