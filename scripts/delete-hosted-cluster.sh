#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🗑️  Deleting hosted cluster..."

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
    echo "📋 Found kubeconfig, checking for hosted cluster in ACM..."
    
    # Try to delete via ACM if cluster exists
    if oc get hostedcluster "$CLUSTER_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo "   Found hosted cluster in ACM: $CLUSTER_NAME"
        echo "   Deleting hosted cluster..."
        oc delete hostedcluster "$CLUSTER_NAME" -n "$NAMESPACE" --wait=true --timeout=30m || true
        echo "✅ Hosted cluster deletion initiated in ACM"
    else
        echo "   Hosted cluster not found in ACM namespace $NAMESPACE"
    fi
else
    echo "⚠️  Warning: kubeconfig not found. Cannot delete via ACM."
    echo "   You may need to manually clean up resources in AWS."
fi

# Also try hcp CLI deletion method
if command -v hcp &> /dev/null; then
    echo ""
    echo "🗑️  Attempting deletion via hcp CLI..."
    
    # Check if STS credentials exist
    if [ -f "$PROJECT_DIR/tmp/sts-creds.json" ]; then
        REGION=$(yq eval '.hosted_cluster.region' "$PROJECT_DIR/config.yaml")
        
        echo "   Deleting hosted cluster: $CLUSTER_NAME in region: $REGION"
        hcp destroy cluster aws \
            --name "$CLUSTER_NAME" \
            --region "$REGION" \
            --sts-creds "$PROJECT_DIR/tmp/sts-creds.json" || {
            echo "⚠️  Warning: hcp destroy command failed. The cluster may already be deleted or may need manual cleanup."
        }
    else
        echo "   STS credentials not found. Skipping hcp CLI deletion."
    fi
fi

echo ""
echo "✅ Hosted cluster deletion process completed!"
echo "   Note: Some resources may take time to be fully removed from AWS."

