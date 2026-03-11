# AI Log Intelligence

Event-driven pipeline that detects ERROR/WARN in application logs, analyzes them with **Ollama (phi3:mini)** on EC2, and sends enriched AI-generated alerts via SNS email.

---

## Problem Statement

Application logs often flood teams with raw ERROR and WARN lines. It's hard to see what's actually wrong, what's likely causing it, and what to do next. This project:

- **Reduces noise** by deduplicating log patterns and focusing on the top issues.
- **Adds intelligence** by sending a compact summary to an LLM (Ollama on EC2) for a structured analysis: error summary, root cause, recommended fix, and severity.
- **Delivers actionable alerts** via SNS email so you get one clear message instead of hundreds of log lines.

---

## Project Overview

**AI Log Intelligence** is an AWS-native pipeline that:

1. Ingests application logs (ERROR/WARN) from CloudWatch Logs.
2. Deduplicates and ranks log patterns, then sends a small, representative set to an LLM.
3. Uses **Ollama** (phi3:mini) running on EC2 to produce a structured analysis (summary, root cause, recommended fix, severity).
4. Publishes the result to an SNS topic so subscribers receive a single, readable email alert instead of raw log dumps.

The pipeline is triggered by a CloudWatch alarm when the error count in the log group exceeds a threshold. Lambda handles fetch, deduplication, LLM call, and alert publishing; DynamoDB provides idempotency so the same batch doesn't trigger duplicate alerts within a short window.

---

## Workflow

1. **Logs** — An app (or the EC2 host) writes logs; CloudWatch Agent ships them to CloudWatch Logs.
2. **Trigger** — A metric filter counts ERROR/WARN events; when the count crosses the threshold, a CloudWatch alarm invokes the Lambda.
3. **Lambda** — Fetches the last 15 minutes of ERROR/WARN logs, deduplicates by pattern, keeps the **top 5** groups, and sends **one example log** per group to Ollama to keep the prompt small.
4. **Ollama** — phi3:mini in JSON mode (max 200 tokens) returns a structured analysis: error summary, root cause, recommended fix, severity.
5. **SNS** — Lambda publishes the analysis (plus sample log lines) to an SNS topic; email subscribers get the alert. Idempotency (DynamoDB) avoids duplicate alerts for the same log batch within 5 minutes.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Infrastructure** | Terraform (AWS), EC2, VPC |
| **Logging** | CloudWatch Logs, CloudWatch Agent |
| **Orchestration** | CloudWatch Metric Filter, CloudWatch Alarm |
| **Compute** | AWS Lambda (Python 3.x), EC2 (Ubuntu) |
| **AI / LLM** | Ollama, phi3:mini |
| **Notifications** | Amazon SNS (email) |
| **State** | DynamoDB (idempotency) |
| **Runtime** | Python (Lambda), bash (EC2 user data) |

---

## Project Structure

```
ai-log-intelligence/
├── README.md                # This file — overview, workflow, structure
├── .gitignore               # Terraform state, tfvars, lambda.zip, credentials, etc.
├── output/                  # Screenshots / artifacts (e.g. CloudWatch alarm, SNS alert)
├── docs/                    # Documentation
│   ├── Configuration.md    # Prerequisites, deploy, post-deploy, variables, troubleshooting
│   └── architecture-diagram.png
│
├── terraform/               # Infrastructure as code
│   ├── main.tf              # Root: modules, log group, provider
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars     # Your values (not committed; see .gitignore)
│   └── modules/
│       ├── sns/             # SNS topic (+ policy, prevent_destroy)
│       ├── ec2/             # Ollama host + CloudWatch Agent
│       │   ├── main.tf
│       │   └── user_data.sh.tpl
│       ├── lambda/          # IAM, DynamoDB, Lambda function
│       │   ├── main.tf
│       │   └── lambda.zip   # Built by build_lambda.sh (not committed)
│       └── cloudwatch/      # Metric filter + alarm + permission
│
├── lambda/                  # Lambda function source
│   └── src/
│       └── handler.py       # Fetch logs, dedupe, call Ollama, parse, publish SNS
│
└── scripts/
    └── build_lambda.sh      # Packages lambda/src → terraform/modules/lambda/lambda.zip
```

---

## Setup / Deployment

For prerequisites, deploy steps, post-deploy steps, key variables, troubleshooting, security notes, teardown, and Lambda environment variables, see **[docs/Configuration.md](docs/Configuration.md)**.

---

## Future Improvements

- **Multiple notification channels** — Add SNS subscriptions for Slack, PagerDuty, or webhooks.
- **Configurable model** — Support different Ollama models or parameters via Terraform/Lambda env vars.
- **Warm-up schedule** — EventBridge rule to invoke a lightweight Lambda or curl Ollama periodically so the model stays loaded.
- **Multi–log group** — Extend the pipeline to aggregate ERROR/WARN from multiple log groups with a single alarm.
