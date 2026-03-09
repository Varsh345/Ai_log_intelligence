#!/bin/bash
# EC2 User Data — AI Log Intelligence host
# Idempotent: marker files prevent re-running steps on reboot.
set -euo pipefail
exec > /var/log/user-data.log 2>&1

LOG_GROUP="${log_group_name}"
AWS_REGION="${aws_region}"

echo "=== AI Log Intelligence Bootstrap ==="
echo "Log group : $LOG_GROUP"
echo "Region    : $AWS_REGION"
date

# ── 1. Disk expansion ─────────────────────────────────────────────────────────
growpart /dev/xvda 1  2>/dev/null || growpart /dev/nvme0n1p1 1 2>/dev/null || true
resize2fs /dev/xvda1  2>/dev/null || resize2fs /dev/nvme0n1p1 2>/dev/null || true

# ── 2. Base packages ──────────────────────────────────────────────────────────
apt-get update -y
apt-get install -y python3 python3-pip curl wget unzip jq

# ── 3. Log file setup ─────────────────────────────────────────────────────────
mkdir -p /var/log
touch /var/log/app.log
chmod 644 /var/log/app.log

# ── 4. Log generator (systemd service) ───────────────────────────────────────
if [ ! -f /etc/systemd/system/log-generator.service ]; then
  cat > /usr/local/bin/log-generator.py << 'PYSCRIPT'
#!/usr/bin/env python3
"""Demo log generator — writes INFO/WARN/ERROR to /var/log/app.log every 10 s."""
import random
import time
from datetime import datetime, timezone

LEVELS = ["INFO"] * 7 + ["WARN"] * 2 + ["ERROR"] * 1

MESSAGES = {
    "INFO":  [
        "Request processed successfully in {ms}ms",
        "User {uid} authenticated",
        "Cache hit for key session:{uid}",
        "Health check passed",
        "Background job completed",
    ],
    "WARN": [
        "Database connection pool at {pct}% capacity",
        "Response time {ms}ms exceeds soft threshold",
        "Retrying request to downstream service (attempt {n}/3)",
        "Memory usage at {pct}%",
    ],
    "ERROR": [
        "NullPointerException in OrderService.processOrder() at line 142",
        "Connection refused: database host db-primary:5432",
        "Timeout waiting for upstream API after 30000ms",
        "Failed to acquire lock on resource orders:{uid}",
        "OutOfMemoryError: Java heap space",
        "SSL certificate verification failed for https://api.external.com",
        "Unhandled exception in PaymentProcessor: InvalidCardException",
    ],
}

def main():
    while True:
        level = random.choice(LEVELS)
        tmpl  = random.choice(MESSAGES[level])
        msg   = tmpl.format(
            ms  = random.randint(50, 15000),
            uid = random.randint(1000, 9999),
            pct = random.randint(70, 99),
            n   = random.randint(1, 3),
        )
        ts  = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        line = f"{ts} [{level}] app - {msg}\n"
        with open("/var/log/app.log", "a") as f:
            f.write(line)
        time.sleep(10)

if __name__ == "__main__":
    main()
PYSCRIPT
  chmod +x /usr/local/bin/log-generator.py

  cat > /etc/systemd/system/log-generator.service << 'SVCEOF'
[Unit]
Description=AI Log Intelligence Demo Log Generator
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/log-generator.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

  systemctl daemon-reload
  systemctl enable log-generator
  systemctl start log-generator
  echo "Log generator started."
fi

# ── 5. CloudWatch Agent ───────────────────────────────────────────────────────
if ! command -v amazon-cloudwatch-agent-ctl &>/dev/null; then
  CW_DEB="amazon-cloudwatch-agent.deb"
  wget -q "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/$CW_DEB" -O "/tmp/$CW_DEB"
  dpkg -i "/tmp/$CW_DEB"
  rm -f "/tmp/$CW_DEB"
fi

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << CWEOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "CloudWatch Agent configured and started."

# ── 6. Ollama ─────────────────────────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

# Configure Ollama to listen on all interfaces
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'OLEOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
OLEOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# Wait for Ollama API to be ready
echo "Waiting for Ollama API..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Ollama is ready."
    break
  fi
  echo "  attempt $i/30..."
  sleep 5
done

# Pull phi3:mini model (only once)
if [ ! -f /var/lib/ollama/.ollama/models/manifests/registry.ollama.ai/library/phi3/latest ] && \
   [ ! -f /root/.ollama/models/manifests/registry.ollama.ai/library/phi3/latest ]; then
  echo "Pulling phi3:mini..."
  ollama pull phi3:mini
  echo "phi3:mini pulled successfully."
else
  echo "phi3:mini already present."
fi

# ── 7. Sample ERROR/WARN lines for pipeline testing ──────────────────────────
if [ ! -f /var/run/sample-errors-written ]; then
  TS=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  cat >> /var/log/app.log << LOGEOF
$TS [ERROR] app - NullPointerException in OrderService.processOrder() at line 142
$TS [ERROR] app - Connection refused: database host db-primary:5432
$TS [WARN]  app - Database connection pool at 95% capacity
$TS [ERROR] app - Timeout waiting for upstream API after 30000ms
$TS [WARN]  app - Memory usage at 87%
LOGEOF
  touch /var/run/sample-errors-written
  echo "Sample errors written."
fi

echo "=== Bootstrap complete ==="
date
