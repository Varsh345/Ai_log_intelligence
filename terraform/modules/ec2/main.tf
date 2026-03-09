# terraform/modules/ec2/main.tf

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "ollama" {
  name        = "${var.name_prefix}-ollama-sg"
  description = "Security group for Ollama EC2 host"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-ollama-sg" })

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Ollama API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # restrict in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── IAM for CloudWatch Agent ──────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.name_prefix}-ec2-role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "ollama" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ollama.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    log_group_name = var.log_group_name
    aws_region     = var.aws_region
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-ollama-host" })

  lifecycle {
    ignore_changes = [ami]
  }
}
