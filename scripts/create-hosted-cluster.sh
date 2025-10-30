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
echo "   AWS Identity: $(aws sts get-caller-identity --query 'Arn' --output text)"

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

# Check if STS credentials are expired (robust RFC3339 parsing)
STS_EXPIRATION=$(jq -r '.Credentials.Expiration' "$STS_CREDS_FILE" 2>/dev/null || echo "")
if [ -n "$STS_EXPIRATION" ] && [ "$STS_EXPIRATION" != "null" ]; then
    # Try GNU date first
    STS_EXPIRATION_EPOCH=$(date -d "$STS_EXPIRATION" +%s 2>/dev/null || echo "")

    if [ -z "$STS_EXPIRATION_EPOCH" ]; then
        # If ends with Z, try BSD date with Z format
        if echo "$STS_EXPIRATION" | grep -q "Z$"; then
            STS_EXPIRATION_EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$STS_EXPIRATION" +%s 2>/dev/null || echo "")
        else
            # Normalize timezone offset from "+hh:mm" to "+hhmm" for BSD date
            STS_EXPIRATION_NOCOLON=$(echo "$STS_EXPIRATION" | sed -E 's/(.*[+\-][0-9]{2}):([0-9]{2})$/\1\2/')
            STS_EXPIRATION_EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$STS_EXPIRATION_NOCOLON" +%s 2>/dev/null || echo "")
        fi
    fi

    if [ -z "$STS_EXPIRATION_EPOCH" ]; then
        echo "⚠️  Warning: Could not parse STS Expiration time: $STS_EXPIRATION"
        echo "   Skipping expiration check."
    else
        CURRENT_EPOCH=$(date +%s)
        if [ "$STS_EXPIRATION_EPOCH" -lt "$CURRENT_EPOCH" ]; then
            echo "❌ Error: STS credentials in sts-creds.json have expired"
            echo "   Expiration: $STS_EXPIRATION"
            echo "   Please regenerate by running setup-aws-prerequisites.sh"
            exit 1
        fi
        echo "   STS credentials expire at: $STS_EXPIRATION"
    fi
fi

# Create hosted cluster
# Use current working directory for log file
WORK_DIR="${PWD:-$(pwd)}"
HOSTED_CLUSTER_LOG="$WORK_DIR/hosted-cluster-creation.log"

# Verify we can assume the role using the STS credentials (same as hcp CLI will use)
echo "🔍 Verifying role assumption permissions using STS credentials..."
CURRENT_USER_ARN=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "")
if [ -z "$CURRENT_USER_ARN" ]; then
    echo "❌ Error: Cannot determine current AWS user identity"
    exit 1
fi

echo "   Current AWS Identity: $CURRENT_USER_ARN"
echo "   Target Role ARN: $ROLE_ARN"

# Extract STS credentials from sts-creds.json
STS_ACCESS_KEY=$(jq -r '.Credentials.AccessKeyId' "$STS_CREDS_FILE")
STS_SECRET_KEY=$(jq -r '.Credentials.SecretAccessKey' "$STS_CREDS_FILE")
STS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' "$STS_CREDS_FILE")

# Verify STS credentials identity
echo "   Verifying STS credentials identity..."
STS_IDENTITY=$(AWS_ACCESS_KEY_ID="$STS_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$STS_SECRET_KEY" AWS_SESSION_TOKEN="$STS_SESSION_TOKEN" \
    aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "")
if [ -z "$STS_IDENTITY" ]; then
    echo "❌ Error: STS credentials are invalid or expired"
    echo "   Please regenerate by running setup-aws-prerequisites.sh"
    exit 1
fi
echo "   STS Identity: $STS_IDENTITY"

# Check the role trust policy to verify it allows this user
echo "   Checking role trust policy..."
TRUST_POLICY_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query "Role.AssumeRolePolicyDocument.Statement[0].Principal.AWS" --output text 2>/dev/null || echo "")
if [ -n "$TRUST_POLICY_ARN" ]; then
    if echo "$TRUST_POLICY_ARN" | grep -q "$CURRENT_USER_ARN" || echo "$CURRENT_USER_ARN" | grep -q "$(echo $TRUST_POLICY_ARN | tr -d '\"')"; then
        echo "   ✅ Trust policy appears to allow this user"
    else
        echo "   ⚠️  Warning: Trust policy allows: $TRUST_POLICY_ARN"
        echo "   Current user: $CURRENT_USER_ARN"
    fi
fi

# Try to assume the role using STS credentials (same as hcp CLI will use)
echo "   Attempting to assume role using STS credentials..."
ASSUME_ROLE_OUTPUT=$(AWS_ACCESS_KEY_ID="$STS_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$STS_SECRET_KEY" AWS_SESSION_TOKEN="$STS_SESSION_TOKEN" \
    aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "hcp-cluster-creation-check" --duration-seconds 900 2>&1)
ASSUME_ROLE_EXIT=$?

if [ $ASSUME_ROLE_EXIT -ne 0 ]; then
    echo "❌ Error: Cannot assume role $ROLE_ARN using STS credentials"
    echo "   This is the same check that hcp CLI will perform, so cluster creation will fail."
    echo ""
    echo "   Error details:"
    echo "$ASSUME_ROLE_OUTPUT" | head -10
    echo ""
    echo "   Troubleshooting steps:"
    echo "   1. Verify the IAM role trust policy allows: $STS_IDENTITY (or $CURRENT_USER_ARN)"
    echo "   2. Check the role trust policy:"
    echo "      aws iam get-role --role-name $IAM_ROLE_NAME --query 'Role.AssumeRolePolicyDocument'"
    echo "   3. Ensure setup-aws-prerequisites.sh was run and used the correct USER_ARN"
    echo "   4. If your USER_ARN has changed, recreate the role with the correct trust policy"
    echo "   5. Regenerate STS credentials: bash scripts/setup-aws-prerequisites.sh"
    echo ""
    exit 1
else
    echo "✅ Role assumption verified successfully using STS credentials"
fi

# Ensure AWS region is set for the hcp command
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

echo "⏳ Creating hosted cluster: $CLUSTER_NAME (this may take 15-20 minutes)..."
echo "📝 Hosted cluster creation logs will be saved to: $HOSTED_CLUSTER_LOG"
echo "   You can monitor progress with: tail -f $HOSTED_CLUSTER_LOG"
echo "   Using Role ARN: $ROLE_ARN"
echo "   Using STS Creds: $STS_CREDS_FILE"
echo -n "   Creating"

# Run hcp command in background and redirect output to log file
# Ensure AWS credentials are exported for hcp CLI
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

