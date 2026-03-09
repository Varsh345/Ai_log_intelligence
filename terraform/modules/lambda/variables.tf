# terraform/modules/lambda/variables.tf

variable "name_prefix"      { type = string }
variable "lambda_zip_path"  { type = string }
variable "lambda_timeout" {
  type    = number
  default = 120
}
variable "lambda_memory" {
  type    = number
  default = 256
}
variable "log_group_name"   { type = string }
variable "log_group_arn"    { type = string }
variable "sns_topic_arn"    { type = string }
variable "ollama_url"       { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
