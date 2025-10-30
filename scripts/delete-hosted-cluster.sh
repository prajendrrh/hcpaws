#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print message with timestamp
log_msg() {
    echo -e "[$(get_timestamp)] $1"
}

log_msg "🗑️  Deleting hosted cluster..."

# Load configuration
if [ ! -f "$PROJECT_DIR/config.yaml" ]; then
    echo "Error: config.yaml not found."
    exit 1
fi

# Read config values
CLUSTER_NAME=$(yq eval '.hosted_cluster.name' "$PROJECT_DIR/config.yaml")
NAMESPACE=$(yq eval '.hosted_cluster.namespace' "$PROJECT_DIR/config.yaml")

# Setup AWS credentials
if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
    source "$SCRIPT_DIR/setup-aws-credentials.sh"
fi

# Use current working directory to find kubeconfig
WORK_DIR="${PWD:-$(pwd)}"

# Check if kubeconfig exists (for ACM-based deletion)
if [ -f "$WORK_DIR/auth/kubeconfig" ]; then
    export KUBECONFIG="$WORK_DIR/auth/kubeconfig"
    log_msg "📋 Found kubeconfig, checking for hosted cluster in ACM..."
    
    # Try to delete via ACM if cluster exists
    if oc get hostedcluster "$CLUSTER_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_msg "   Found hosted cluster in ACM: $CLUSTER_NAME"
        log_msg "   Deleting hosted cluster..."
        oc delete hostedcluster "$CLUSTER_NAME" -n "$NAMESPACE" --wait=true --timeout=30m || true
        log_msg "✅ Hosted cluster deletion initiated in ACM"
    else
        log_msg "   Hosted cluster not found in ACM namespace $NAMESPACE"
    fi
else
    log_msg "⚠️  Warning: kubeconfig not found. Cannot delete via ACM."
    log_msg "   You may need to manually clean up resources in AWS."
fi

# Also try hcp CLI deletion method
if command -v hcp &> /dev/null; then
    echo ""
    log_msg "🗑️  Attempting deletion via hcp CLI..."
    
    # Check if STS credentials exist (check in same directory as pull secret)
    PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' "$PROJECT_DIR/config.yaml" 2>/dev/null || echo "")
    if [ -n "$PULL_SECRET_FILE" ] && [ -f "$PROJECT_DIR/$PULL_SECRET_FILE" ]; then
        PULL_SECRET_DIR=$(dirname "$PROJECT_DIR/$PULL_SECRET_FILE")
        STS_CREDS_FILE="$PULL_SECRET_DIR/sts-creds.json"
    else
        STS_CREDS_FILE="$PROJECT_DIR/tmp/sts-creds.json"
    fi
    
    if [ -f "$STS_CREDS_FILE" ]; then
        REGION=$(yq eval '.hosted_cluster.region' "$PROJECT_DIR/config.yaml")
        
        log_msg "   Deleting hosted cluster: $CLUSTER_NAME in region: $REGION"
        hcp destroy cluster aws \
            --name "$CLUSTER_NAME" \
            --region "$REGION" \
            --sts-creds "$STS_CREDS_FILE" || {
            log_msg "⚠️  Warning: hcp destroy command failed. The cluster may already be deleted or may need manual cleanup."
        }
    else
        log_msg "   STS credentials not found at $STS_CREDS_FILE. Skipping hcp CLI deletion."
    fi
fi

echo ""
log_msg "✅ Hosted cluster deletion process completed!"
log_msg "   Note: Some resources may take time to be fully removed from AWS."

