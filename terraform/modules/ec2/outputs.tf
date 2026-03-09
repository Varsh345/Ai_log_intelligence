# terraform/modules/ec2/outputs.tf

output "instance_id" {
  value = aws_instance.ollama.id
}

output "public_ip" {
  value = aws_instance.ollama.public_ip
}

output "security_group_id" {
  value = aws_security_group.ollama.id
}
