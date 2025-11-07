#!/bin/bash

# Module 4: Create Hosted Cluster
# This creates the hosted cluster using the hcp CLI

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
log_msg "${BLUE}Module 4: Create Hosted Cluster${NC}"
log_msg "${BLUE}========================================${NC}"
echo ""

# Verify prerequisites
log_msg "Verifying prerequisites..."

# Check config files
if [ ! -f "config.yaml" ]; then
    echo "Error: config.yaml not found!"
    exit 1
fi

if [ ! -f "aws-credentials.env" ]; then
    echo "Error: aws-credentials.env not found!"
    exit 1
fi

# Check if sts-creds.json exists
PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' config.yaml)
PULL_SECRET_DIR=$(dirname "$PULL_SECRET_FILE")
STS_CREDS_FILE="$PULL_SECRET_DIR/sts-creds.json"

if [ ! -f "$STS_CREDS_FILE" ]; then
    echo "Error: sts-creds.json not found at $STS_CREDS_FILE"
    echo "Please run Module 3 first to generate STS credentials."
    exit 1
fi

log_msg "${GREEN}✓ Prerequisites verified${NC}"
echo ""


# Step 7: Create hosted cluster
log_msg "Creating hosted cluster..."
log_msg "⚠️  This will take 15-20 minutes. Please be patient..."
echo ""

bash scripts/create-hosted-cluster.sh || exit 1
echo ""

log_msg "${GREEN}========================================${NC}"
log_msg "${GREEN}✅ Module 4 completed successfully!${NC}"
log_msg "${GREEN}Hosted Cluster has been created!${NC}"
log_msg "${GREEN}========================================${NC}"
echo ""
log_msg "🎉 All modules completed successfully!"
log_msg "Your OpenShift Management Cluster with ACM and Hosted Cluster are ready!"

