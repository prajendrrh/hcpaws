#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Installing OpenShift Hub Cluster..."

# Setup AWS credentials in ~/.aws/credentials and ~/.aws/config
# Source the script instead of running it to preserve environment variables
if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
    source "$SCRIPT_DIR/setup-aws-credentials.sh"
fi

# Ensure AWS SDK loads config from ~/.aws directory
export AWS_SDK_LOAD_CONFIG=1

# Use current working directory
WORK_DIR="${PWD:-$(pwd)}"

# Check if install-config.yaml exists
if [ ! -f "$WORK_DIR/install-config.yaml" ]; then
    echo "Error: install-config.yaml not found in current directory ($WORK_DIR). Please run generate-install-config.sh first."
    exit 1
fi

# Create cluster in current directory
echo "⏳ Creating cluster (this will take 30-60 minutes)..."
cd "$WORK_DIR"

# Verify AWS credentials are available
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ Error: AWS credentials not found in environment variables"
    echo "   Attempting to reload from aws-credentials.env..."
    source "$PROJECT_DIR/aws-credentials.env"
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
fi

# Verify credentials file exists
if [ ! -f ~/.aws/credentials ]; then
    echo "❌ Error: ~/.aws/credentials not found"
    exit 1
fi

echo "✅ AWS credentials verified and ready"

# Run openshift-install with credentials explicitly available
openshift-install create cluster --dir . --log-level debug

echo "✅ Hub cluster installation completed!"

