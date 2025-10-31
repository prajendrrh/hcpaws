#!/bin/bash

# Module 2: Install ACM (Advanced Cluster Management)
# This installs ACM on the management cluster

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
log_msg "${BLUE}Module 2: Install ACM${NC}"
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

# Step 5: Install ACM
log_msg "Installing ACM (Advanced Cluster Management)..."
cd "$WORK_DIR" || exit 1
bash "$SCRIPT_DIR/scripts/install-acm.sh" || exit 1
cd "$SCRIPT_DIR" || true
echo ""

log_msg "${GREEN}========================================${NC}"
log_msg "${GREEN}✅ Module 2 completed successfully!${NC}"
log_msg "${GREEN}ACM is installed and ready${NC}"
log_msg "${GREEN}========================================${NC}"
echo ""
log_msg "You can now proceed to Module 3: Setup Prerequisites for Hosted Cluster"
log_msg "Run: bash module-3-setup-hosted-prerequisites.sh"

