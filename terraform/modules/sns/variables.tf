# terraform/modules/sns/variables.tf

variable "topic_name" {
  description = "SNS topic name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
