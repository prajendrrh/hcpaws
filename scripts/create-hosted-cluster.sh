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

# Setup AWS credentials in ~/.aws/credentials and ~/.aws/config
# Source instead of bash to preserve environment variables
if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
    source "$SCRIPT_DIR/setup-aws-credentials.sh"
fi

# Ensure AWS profile is set to default and export it
export AWS_PROFILE=default
export AWS_DEFAULT_PROFILE=default

# Verify AWS credentials are available
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
        source "$PROJECT_DIR/aws-credentials.env"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    fi
fi

# Verify we can call AWS CLI
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ Error: AWS credentials are not configured or invalid"
    echo "   Please ensure AWS credentials are set up correctly"
    exit 1
fi

echo "✅ AWS credentials verified"

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
if ! ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query "Role.Arn" --output text 2>&1); then
    echo "❌ Error: IAM role '$IAM_ROLE_NAME' does not exist!"
    echo ""
    echo "   The AWS prerequisites have not been set up yet."
    echo "   Please run the setup-aws-prerequisites.sh script first:"
    echo ""
    echo "   bash $SCRIPT_DIR/setup-aws-prerequisites.sh"
    echo ""
    echo "   This script will create:"
    echo "   - S3 bucket for OIDC provider"
    echo "   - IAM role ($IAM_ROLE_NAME) with necessary permissions"
    echo "   - STS session credentials"
    echo ""
    exit 1
fi
echo "  Role ARN: $ROLE_ARN"

# Get pull secret file path first to determine sts-creds.json location
PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' "$PROJECT_DIR/config.yaml")
if [ ! -f "$PROJECT_DIR/$PULL_SECRET_FILE" ]; then
    echo "Error: Pull secret file not found: $PROJECT_DIR/$PULL_SECRET_FILE"
    exit 1
fi

# Get the directory where pull secret is located - sts-creds.json should be in the same directory
PULL_SECRET_DIR=$(dirname "$PROJECT_DIR/$PULL_SECRET_FILE")
STS_CREDS_FILE="$PULL_SECRET_DIR/sts-creds.json"

# Check for required files
if [ ! -f "$STS_CREDS_FILE" ]; then
    echo "Error: sts-creds.json not found at $STS_CREDS_FILE"
    echo "   Expected location: same directory as pull secret ($PULL_SECRET_DIR)"
    echo "   Please run setup-aws-prerequisites.sh first."
    exit 1
fi

# Verify STS credentials file is valid JSON and contains required fields
if ! jq -e '.Credentials.AccessKeyId and .Credentials.SecretAccessKey and .Credentials.SessionToken' "$STS_CREDS_FILE" >/dev/null 2>&1; then
    echo "❌ Error: sts-creds.json is invalid or missing required fields"
    echo "   Expected format: JSON with Credentials.AccessKeyId, Credentials.SecretAccessKey, Credentials.SessionToken"
    echo "   Please regenerate by running setup-aws-prerequisites.sh"
    exit 1
fi

# Create hosted cluster
# Use current working directory for log file
WORK_DIR="${PWD:-$(pwd)}"
HOSTED_CLUSTER_LOG="$WORK_DIR/hosted-cluster-creation.log"

# Ensure AWS region is set for the hcp command
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

echo "⏳ Creating hosted cluster: $CLUSTER_NAME (this may take 15-20 minutes)..."
echo "📝 Hosted cluster creation logs will be saved to: $HOSTED_CLUSTER_LOG"
echo "   You can monitor progress with: tail -f $HOSTED_CLUSTER_LOG"
echo "   Using Role ARN: $ROLE_ARN"
echo "   Using STS Creds: $STS_CREDS_FILE"

# Retry logic for IAM propagation delays (AWS IAM can take time to propagate)
MAX_RETRIES=3
RETRY_DELAY=10
RETRY_COUNT=0
EXIT_CODE=1

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ $EXIT_CODE -ne 0 ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo "   Retry attempt $RETRY_COUNT/$((MAX_RETRIES-1)) after ${RETRY_DELAY}s delay (IAM propagation)..."
        sleep $RETRY_DELAY
        RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
    fi
    
    echo -n "   Creating"
    
    # Run hcp command in background and redirect output to log file
    hcp create cluster aws \
        --name "$CLUSTER_NAME" \
        --infra-id "$INFRA_ID" \
        --base-domain "$BASE_DOMAIN" \
        --sts-creds "$STS_CREDS_FILE" \
        --pull-secret "$PROJECT_DIR/$PULL_SECRET_FILE" \
        --region "$REGION" \
        --zones "$ZONES" \
        --generate-ssh \
        --node-pool-replicas "$NODE_POOL_REPLICAS" \
        --namespace "$NAMESPACE" \
        --role-arn "$ROLE_ARN" \
        --release-image "$RELEASE_IMAGE" > "$HOSTED_CLUSTER_LOG" 2>&1 &
    HCP_PID=$!
    
    # Show progress while waiting
    COUNTER=0
    while kill -0 $HCP_PID 2>/dev/null; do
        sleep 60
        COUNTER=$((COUNTER + 1))
        echo -n "."
        # Show message every 5 minutes
        if [ $((COUNTER % 5)) -eq 0 ]; then
            echo ""
            echo "   Still creating... ($((COUNTER)) minutes elapsed - check $HOSTED_CLUSTER_LOG for details)"
            echo -n "   Creating"
        fi
    done
    wait $HCP_PID
    EXIT_CODE=$?
    echo ""
    
    # Check if failure is due to IAM/permissions (retryable errors)
    if [ $EXIT_CODE -ne 0 ]; then
        if grep -q "AccessDenied.*sts:AssumeRole" "$HOSTED_CLUSTER_LOG" 2>/dev/null || \
           grep -q "is not authorized to perform.*sts:AssumeRole" "$HOSTED_CLUSTER_LOG" 2>/dev/null || \
           grep -q "UnauthorizedOperation" "$HOSTED_CLUSTER_LOG" 2>/dev/null || \
           grep -q "is not authorized to perform this operation" "$HOSTED_CLUSTER_LOG" 2>/dev/null; then
            echo "   ⚠️  Failed with IAM/permissions error - likely IAM policy propagation delay"
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
                echo "   ❌ Max retries reached. This may be a permissions issue."
            fi
        else
            # Non-retryable error, exit immediately
            break
        fi
    fi
done

# Check if creation was successful
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ Hosted cluster creation failed!"
    echo "   Check the log file for details: $HOSTED_CLUSTER_LOG"
    echo "   Last 50 lines of log:"
    tail -50 "$HOSTED_CLUSTER_LOG"
    exit $EXIT_CODE
fi

echo "✅ Hosted cluster creation completed!"
echo "📝 Full creation log saved to: $HOSTED_CLUSTER_LOG"
