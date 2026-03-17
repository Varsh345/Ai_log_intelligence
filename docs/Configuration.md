# Configuration & Deployment

Use this guide after cloning the **AI Log Intelligence** repo. It covers prerequisites, deployment steps, Terraform variables, troubleshooting, security, teardown, and Lambda environment variables so anyone can configure and run the pipeline in their own AWS account.

---

## Prerequisites

Before you begin, ensure you have:

| Requirement | Detail |
|-------------|--------|
| **AWS Account** | Any region (e.g. `us-east-1`); set in `terraform.tfvars` as `aws_region`. |
| **AWS credentials** | Access Key ID + Secret (IAM user or role). Use `aws configure` or export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`. |
| **EC2 Key Pair** | Create in the AWS Console (EC2 → Key Pairs) in your chosen region. You will need the key name and the `.pem` file for SSH. |
| **VPC + Subnet** | Use your default VPC or a custom one. The subnet must be in an Availability Zone that supports your instance type (e.g. for `m6i.xlarge`, avoid `us-east-1e`; use `us-east-1a`, `1b`, `1c`, `1d`, or `1f`). |
| **Terraform** | Version ≥ 1.5. Install: `brew install terraform` or [tfenv](https://github.com/tfutils/tfenv). |
| **zip** | Required to build the Lambda package (usually pre-installed on macOS/Linux). |

---

## 1. Create Terraform variables file

Copy the example (if present) or create `terraform/terraform.tfvars` with your values. **Minimum required:**

```hcl
aws_region   = "us-east-1"          # Your AWS region
project_name = "ai-log-intelligence"
environment  = "prod"

# Required: replace with your values
ssh_key_name = "your-ec2-key-name"  # Name of the EC2 Key Pair in AWS
vpc_id       = "vpc-xxxxxxxx"       # Your VPC ID (e.g. default VPC)
subnet_id    = "subnet-xxxxxxxx"    # A public subnet in the VPC (AZ that supports your instance type)

allowed_ssh_cidr = "0.0.0.0/0"     # Restrict in production (e.g. your IP/32)

# Optional: defaults are usually fine
log_group_name        = "/aws/ec2/ai-log-intelligence/app"
log_retention_days    = 14
metric_namespace      = "AILogIntelligence"
error_count_threshold = 1
alarm_period          = 60
sns_topic_name        = "ai-log-intelligence-prod-alerts"
ec2_instance_type     = "m6i.xlarge"
ec2_root_volume_size  = 40
lambda_timeout_seconds = 120
lambda_memory_mb       = 256
```

---

## 2. Build the Lambda package

From the repo root:

```bash
./scripts/build_lambda.sh
```

This produces `terraform/modules/lambda/lambda.zip`. Run this before the first `terraform apply` and whenever you change `lambda/src/`.

---

## 3. Set AWS credentials and deploy with Terraform

Export credentials (or use `aws configure`), then run Terraform from the `terraform` directory:

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1

cd terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Confirm with `yes` when prompted. Note the outputs (e.g. `ec2_public_ip`, `sns_topic_arn`, `idempotency_table_name`, `lambda_function_name`); you will use them in the next steps.

---

## 4. Post-deploy configuration

### 4.1 Subscribe your email to SNS alerts

Use the SNS topic ARN from Terraform output (so it works for any account/region):

```bash
# Get your topic ARN and subscribe (replace your-email@example.com with your email)
SNS_ARN=$(cd terraform && terraform output -raw sns_topic_arn)
aws sns subscribe \
  --topic-arn "$SNS_ARN" \
  --protocol email \
  --notification-endpoint "your-email@example.com" \
  --region us-east-1
```

Then **confirm the subscription** via the link sent to your email.

### 4.2 Wait for EC2 (Ollama) bootstrap (~5–10 min)

Lambda runs inside the VPC and uses the EC2 **private IP** for `OLLAMA_URL` to reach Ollama. For SSH and verification from your own machine, use the IP that matches how you connect:

- **From the internet (your laptop):** use the EC2 **public** IP.
- **From within the VPC (e.g. bastion or VPN):** use the EC2 **private** IP (e.g. from EC2 console or `aws ec2 describe-instances`).

```bash
# From repo root — use public IP for SSH from your laptop
EC2_IP=$(cd terraform && terraform output -raw ec2_public_ip)
echo "EC2 IP (for SSH): $EC2_IP"

# If you connect from inside the VPC, set EC2_IP to the instance private IP instead
ssh -i ~/.ssh/your-key.pem ubuntu@$EC2_IP 'tail -f /var/log/user-data.log'
```

Wait until you see `=== Bootstrap complete ===`.

### 4.3 Verify Ollama is running

```bash
curl "http://$EC2_IP:11434/api/tags"
```

You should see JSON listing `phi3:mini`. Optionally keep Ollama warm with a periodic request to reduce "No response from model" when the alarm fires.

### 4.4 Test the pipeline (optional)

Lambda can run up to ~2 minutes. Use **async invocation** to avoid CLI timeouts. Use Terraform outputs for the idempotency table and function name so it works in any deployment:

```bash
# Get resource names from your deployment
TABLE_NAME=$(cd terraform && terraform output -raw idempotency_table_name)
FUNC_NAME=$(cd terraform && terraform output -raw lambda_function_name)
REGION=us-east-1   # or your terraform.tfvars aws_region

# Clear idempotency so this run actually calls Ollama
aws dynamodb delete-item \
  --table-name "$TABLE_NAME" \
  --key '{"id": {"S": "last_run"}}' \
  --region "$REGION"

# Invoke Lambda (async)
aws lambda invoke \
  --function-name "$FUNC_NAME" \
  --payload '{}' \
  --invocation-type Event \
  /tmp/out.json \
  --region "$REGION"
```

Wait 1–2 minutes and check your SNS email. View the run in CloudWatch: log group `/aws/lambda/<lambda_function_name>`.

---

## Troubleshooting

| Symptom | What to check |
|--------|----------------|
| Email says "No response from model" | Ollama on EC2 may be cold or unreachable. Ensure EC2 is running, security group allows inbound 11434, and consider warming Ollama (e.g. periodic `curl`). Check Lambda logs in CloudWatch for `Ollama request failed` or timeouts. |
| Invoke returns `skipped_idempotency` | Same log batch was processed recently. Clear the idempotency item (see step 4.4) to force a fresh run, or wait for new logs. |
| CLI "Read timeout" when invoking Lambda | Use `--invocation-type Event` and check the result via SNS email and CloudWatch logs. |
| Terraform: instance type not supported in AZ | Your `subnet_id` is in an AZ where the chosen `ec2_instance_type` is not offered (e.g. m6i.xlarge not in us-east-1e). Pick a subnet in us-east-1a, 1b, 1c, 1d, or 1f. |

---

## Teardown

To remove all resources created by Terraform:

```bash
cd terraform
terraform destroy -var-file=terraform.tfvars
```

Confirm with `yes`. This destroys the EC2 instance, Lambda, SNS topic (if allowed), DynamoDB table, CloudWatch resources, etc.

---

## Environment Variables (Lambda)

The Lambda function receives these environment variables; **Terraform sets them automatically** from your tfvars and module outputs. You do not need to set them in the AWS Console.

| Variable | Description |
|----------|-------------|
| `LOG_GROUP_NAME` | CloudWatch Log Group to fetch ERROR/WARN events from (from `log_group_name`). |
| `SNS_TOPIC_ARN` | ARN of the SNS topic for alerts (from SNS module output). |
| `OLLAMA_URL` | Full URL of the Ollama API, e.g. `http://<ec2_public_ip>:11434/api/generate` (from EC2 module output). |
| `IDEMPOTENCY_TABLE_NAME` | DynamoDB table name for idempotency (from Lambda module output; optional). |

These are wired in `terraform/modules/lambda/main.tf`; changing region, project name, or outputs will reflect here automatically.
