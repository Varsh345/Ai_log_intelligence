# terraform/modules/ec2/variables.tf

variable "name_prefix" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "m6i.xlarge"
}

variable "root_volume_size" {
  type    = number
  default = 40
}

variable "key_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "log_group_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
