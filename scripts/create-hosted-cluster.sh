#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Creating hosted cluster..."

# Load configuration
if [ ! -f "$PROJECT_DIR/config.yaml" ]; then
    echo "Error: config.yaml not found."
    exit 1
fi

# Read config values using yq
CLUSTER_NAME=$(yq eval '.hosted_cluster.name' "$PROJECT_DIR/config.yaml")
INFRA_ID=$(yq eval '.hosted_cluster.infra_id' "$PROJECT_DIR/config.yaml")
BASE_DOMAIN=$(yq eval '.hosted_cluster.base_domain' "$PROJECT_DIR/config.yaml")
REGION=$(yq eval '.hosted_cluster.region' "$PROJECT_DIR/config.yaml")
ZONES=$(yq eval '.hosted_cluster.zones' "$PROJECT_DIR/config.yaml")
NODE_POOL_REPLICAS=$(yq eval '.hosted_cluster.node_pool_replicas' "$PROJECT_DIR/config.yaml")
NAMESPACE=$(yq eval '.hosted_cluster.namespace' "$PROJECT_DIR/config.yaml")
RELEASE_IMAGE=$(yq eval '.hosted_cluster.release_image' "$PROJECT_DIR/config.yaml")
IAM_ROLE_NAME=$(yq eval '.aws.iam_role.name' "$PROJECT_DIR/config.yaml")

# Get IAM role ARN
echo "🔍 Getting IAM role ARN..."
ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query "Role.Arn" --output text)
echo "  Role ARN: $ROLE_ARN"

# Check for required files
if [ ! -f "$PROJECT_DIR/tmp/sts-creds.json" ]; then
    echo "Error: sts-creds.json not found. Please run setup-aws-prerequisites.sh first."
    exit 1
fi

PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' "$PROJECT_DIR/config.yaml")
if [ ! -f "$PROJECT_DIR/$PULL_SECRET_FILE" ]; then
    echo "Error: Pull secret file not found: $PROJECT_DIR/$PULL_SECRET_FILE"
    exit 1
fi

# Create hosted cluster
echo "⏳ Creating hosted cluster: $CLUSTER_NAME (this may take 15-20 minutes)..."
hcp create cluster aws \
    --name "$CLUSTER_NAME" \
    --infra-id "$INFRA_ID" \
    --base-domain "$BASE_DOMAIN" \
    --sts-creds "$PROJECT_DIR/tmp/sts-creds.json" \
    --pull-secret "$PROJECT_DIR/$PULL_SECRET_FILE" \
    --region "$REGION" \
    --zones "$ZONES" \
    --generate-ssh \
    --node-pool-replicas "$NODE_POOL_REPLICAS" \
    --namespace "$NAMESPACE" \
    --role-arn "$ROLE_ARN" \
    --release-image "$RELEASE_IMAGE"

echo "✅ Hosted cluster creation completed!"

