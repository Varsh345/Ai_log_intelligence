#!/usr/bin/env bash
# scripts/build_lambda.sh
# Packages the Lambda function into a zip for Terraform.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${REPO_ROOT}/lambda/src"
OUT_DIR="${REPO_ROOT}/terraform/modules/lambda"
ZIP_FILE="${OUT_DIR}/lambda.zip"

echo "▶ Building Lambda package..."
echo "  Source : ${SRC_DIR}"
echo "  Output : ${ZIP_FILE}"

# Clean old zip
rm -f "${ZIP_FILE}"

# Build zip from src directory
cd "${SRC_DIR}"
zip -r "${ZIP_FILE}" . -x "*.pyc" -x "__pycache__/*" -x "*.egg-info/*"

echo "✅ Lambda package built: ${ZIP_FILE}"
ls -lh "${ZIP_FILE}"
