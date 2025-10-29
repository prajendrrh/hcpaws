#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔑 Setting up AWS credentials..."

# Check if config.yaml exists
if [ ! -f "$PROJECT_DIR/config.yaml" ]; then
    echo "Error: config.yaml not found."
    exit 1
fi

# Check if aws-credentials.env exists
if [ ! -f "$PROJECT_DIR/aws-credentials.env" ]; then
    echo "Error: aws-credentials.env not found."
    exit 1
fi

# Source AWS credentials
source "$PROJECT_DIR/aws-credentials.env"

# Read AWS region from config.yaml
AWS_REGION=$(yq eval '.hub_cluster.region' "$PROJECT_DIR/config.yaml" 2>/dev/null || yq eval '.hosted_cluster.region' "$PROJECT_DIR/config.yaml" 2>/dev/null || echo "us-east-1")

# Create .aws directory if it doesn't exist
mkdir -p ~/.aws

# Create/update ~/.aws/credentials
echo "📝 Updating ~/.aws/credentials..."
cat > ~/.aws/credentials <<EOF
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

# Create/update ~/.aws/config
echo "📝 Updating ~/.aws/config..."
cat > ~/.aws/config <<EOF
[default]
region = ${AWS_REGION}
output = json
EOF

# Export environment variables as well (for tools that use them)
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="${AWS_REGION}"

echo "✅ AWS credentials configured in ~/.aws/credentials and ~/.aws/config"
echo "✅ AWS region set to: ${AWS_REGION}"

