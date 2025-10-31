#!/bin/bash

# Module 1: Create Management (Hub) Cluster
# This includes: prerequisites check, install-config generation, hub cluster installation, and verification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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
log_msg "${BLUE}Module 1: Create Management (Hub) Cluster${NC}"
log_msg "${BLUE}========================================${NC}"
echo ""

# Check prerequisites
log_msg "Step 1: Checking prerequisites..."
bash scripts/check-prerequisites.sh || exit 1
echo ""

# Check for configuration files
if [ ! -f "config.yaml" ]; then
    echo "Error: config.yaml not found!"
    echo "Please copy config.yaml.example to config.yaml and fill in your values."
    exit 1
fi

if [ ! -f "aws-credentials.env" ]; then
    echo "Error: aws-credentials.env not found!"
    echo "Please copy aws-credentials.env.example to aws-credentials.env and fill in your AWS credentials."
    exit 1
fi

PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' config.yaml)
if [ ! -f "$PULL_SECRET_FILE" ]; then
    echo "Error: Pull secret file not found: $PULL_SECRET_FILE"
    echo "Please copy pull-secret.txt.example to $PULL_SECRET_FILE and paste your OpenShift pull secret."
    exit 1
fi

log_msg "${GREEN}✓ Configuration files found${NC}"
echo ""

# Step 2: Generate install-config.yaml
log_msg "Step 2: Generating install-config.yaml..."
bash scripts/generate-install-config.sh || exit 1
echo ""

# Step 3: Install Hub Cluster
log_msg "Step 3: Installing OpenShift Hub Cluster..."
log_msg "⚠️  This will take 30-60 minutes. Please be patient..."
bash scripts/install-hub-cluster.sh || exit 1
echo ""

# Step 4: Verify cluster is ready
log_msg "Step 4: Verifying cluster is ready..."
bash scripts/verify-cluster-ready.sh || exit 1
echo ""

log_msg "${GREEN}========================================${NC}"
log_msg "${GREEN}✅ Module 1 completed successfully!${NC}"
log_msg "${GREEN}Management (Hub) Cluster is ready${NC}"
log_msg "${GREEN}========================================${NC}"
echo ""
log_msg "You can now proceed to Module 2: Install ACM"
log_msg "Run: bash acm.sh"

