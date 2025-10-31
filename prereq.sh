#!/bin/bash

# Module 3: Setup Prerequisites for Hosted Cluster Creation
# This sets up AWS resources: S3 bucket, IAM role, OIDC provider, STS credentials

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to print message with timestamp
log_msg() {
    echo -e "[$(get_timestamp)] $1"
}

log_msg "${BLUE}========================================${NC}"
log_msg "${BLUE}Module 3: Setup Prerequisites for Hosted Cluster${NC}"
log_msg "${BLUE}========================================${NC}"
echo ""

# Verify kubeconfig exists
if [ -f "installer/auth/kubeconfig" ]; then
    WORK_DIR="$SCRIPT_DIR/installer"
elif [ -f "auth/kubeconfig" ]; then
    WORK_DIR="."
else
    echo "⚠️  Error: Could not find kubeconfig."
    echo "   Please ensure Module 1 completed successfully."
    echo "   Kubeconfig should be in installer/auth/kubeconfig or auth/kubeconfig"
    exit 1
fi

log_msg "Using kubeconfig from: $WORK_DIR/auth/kubeconfig"
echo ""

# Step 6: Setup AWS prerequisites for hosted cluster
log_msg "Setting up AWS prerequisites for hosted cluster..."
log_msg "This includes:"
log_msg "  - S3 bucket for OIDC provider"
log_msg "  - IAM role with necessary permissions"
log_msg "  - OIDC provider secret in cluster"
log_msg "  - STS session credentials"
echo ""

cd "$WORK_DIR" || exit 1
bash "$SCRIPT_DIR/scripts/setup-aws-prerequisites.sh" || exit 1
cd "$SCRIPT_DIR" || true
echo ""

log_msg "${GREEN}========================================${NC}"
log_msg "${GREEN}✅ Module 3 completed successfully!${NC}"
log_msg "${GREEN}AWS prerequisites are ready${NC}"
log_msg "${GREEN}========================================${NC}"
echo ""
log_msg "⚠️  IMPORTANT: Wait a few minutes before proceeding to Module 4"
log_msg "   This allows AWS IAM policies and ConfigMaps to fully propagate"
log_msg ""
log_msg "You can now proceed to Module 4: Create Hosted Cluster"
log_msg "Run: bash hosted.sh"

