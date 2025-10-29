#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "⚠️  WARNING: This will delete EVERYTHING including the management cluster!"
echo ""
read -p "Are you sure you want to continue? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deletion cancelled."
    exit 0
fi

echo ""
echo "🗑️  Starting full deletion process..."

# Step 1: Delete hosted cluster first (if it exists)
echo ""
echo "Step 1: Deleting hosted cluster..."
if [ -f "$PROJECT_DIR/config.yaml" ]; then
    bash "$SCRIPT_DIR/delete-hosted-cluster.sh" || echo "   Hosted cluster deletion completed or skipped"
else
    echo "   Config file not found, skipping hosted cluster deletion"
fi

# Step 2: Delete AWS prerequisites
echo ""
echo "Step 2: Cleaning up AWS prerequisites..."

# Setup AWS credentials
if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
    source "$SCRIPT_DIR/setup-aws-credentials.sh"
fi

if [ -f "$PROJECT_DIR/config.yaml" ]; then
    BUCKET_NAME=$(yq eval '.hosted_cluster.s3_bucket.name' "$PROJECT_DIR/config.yaml")
    IAM_ROLE_NAME=$(yq eval '.aws.iam_role.name' "$PROJECT_DIR/config.yaml")
    
    # Delete S3 bucket
    if [ -n "$BUCKET_NAME" ]; then
        echo "   Deleting S3 bucket: $BUCKET_NAME..."
        aws s3 rb s3://"$BUCKET_NAME" --force 2>/dev/null || echo "   Bucket may not exist or has objects"
    fi
    
    # Delete IAM role
    if [ -n "$IAM_ROLE_NAME" ]; then
        echo "   Deleting IAM role: $IAM_ROLE_NAME..."
        # Delete role policies first
        aws iam list-role-policies --role-name "$IAM_ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null | \
            tr '\t' '\n' | while read -r policy; do
                if [ -n "$policy" ]; then
                    aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$policy" 2>/dev/null || true
                fi
            done
        # Delete the role
        aws iam delete-role --role-name "$IAM_ROLE_NAME" 2>/dev/null || echo "   Role may not exist"
    fi
fi

# Step 3: Delete management cluster
echo ""
echo "Step 3: Deleting management cluster..."

# Find kubeconfig
WORK_DIR="${PWD:-$(pwd)}"
INSTALL_DIR=""

if [ -f "$WORK_DIR/auth/kubeconfig" ]; then
    INSTALL_DIR="$WORK_DIR"
elif [ -f "$PROJECT_DIR/installer/auth/kubeconfig" ]; then
    INSTALL_DIR="$PROJECT_DIR/installer"
else
    echo "⚠️  Warning: Could not find kubeconfig. Cannot automatically delete cluster."
    echo "   You may need to manually delete the cluster via AWS console or destroy infrastructure manually."
    INSTALL_DIR="$WORK_DIR"
fi

if [ -f "$INSTALL_DIR/auth/kubeconfig" ]; then
    echo "   Found cluster installation at: $INSTALL_DIR"
    export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
    
    # Check if install-config.yaml exists (needed for destroy)
    if [ -f "$INSTALL_DIR/install-config.yaml" ]; then
        cd "$INSTALL_DIR"
        echo "   Destroying cluster infrastructure (this may take 20-30 minutes)..."
        openshift-install destroy cluster --dir . --log-level=info || {
            echo "⚠️  Warning: Cluster destruction had errors. Some resources may need manual cleanup in AWS."
        }
        echo "✅ Cluster infrastructure destruction completed"
    else
        echo "⚠️  Warning: install-config.yaml not found. Cannot use openshift-install destroy."
        echo "   Please manually delete the cluster via AWS console."
    fi
else
    echo "   ⚠️  Warning: kubeconfig not found. Cannot delete cluster automatically."
fi

# Step 4: Clean up local files
echo ""
echo "Step 4: Cleaning up local files..."
echo "   Removing checkpoint file..."
rm -f "$PROJECT_DIR/.checkpoint" || true

echo ""
echo "✅ Full deletion process completed!"
echo ""
echo "Note: Some AWS resources may take time to be fully removed."
echo "Please verify in AWS console that all resources are deleted."

