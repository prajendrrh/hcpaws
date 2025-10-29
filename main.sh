#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CHECKPOINT_FILE="$SCRIPT_DIR/.checkpoint"

# Function to update checkpoint
update_checkpoint() {
    echo "LAST_STEP=$1" > "$CHECKPOINT_FILE"
}

# Function to read checkpoint
read_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        source "$CHECKPOINT_FILE"
        echo "${LAST_STEP:-0}"
    else
        echo "0"
    fi
}

# Check if resume option is requested
RESUME_STEP=0
if [ "$1" = "--resume" ] || [ "$1" = "-r" ]; then
    RESUME_STEP=$(read_checkpoint)
    if [ "$RESUME_STEP" -gt 0 ]; then
        echo -e "${YELLOW}Resuming from step $RESUME_STEP...${NC}"
        echo ""
    else
        echo "No checkpoint found. Starting from beginning."
        RESUME_STEP=0
    fi
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift ACM Hub & Hosted Cluster Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check prerequisites (always run)
if [ "$RESUME_STEP" -le 1 ]; then
    echo "Step 1: Checking prerequisites..."
    bash scripts/check-prerequisites.sh || exit 1
    update_checkpoint 1
fi

# Check for configuration files
if [ ! -f "config.yaml" ]; then
    echo ""
    echo "Error: config.yaml not found!"
    echo "Please copy config.yaml.example to config.yaml and fill in your values."
    exit 1
fi

if [ ! -f "aws-credentials.env" ]; then
    echo ""
    echo "Error: aws-credentials.env not found!"
    echo "Please copy aws-credentials.env.example to aws-credentials.env and fill in your AWS credentials."
    exit 1
fi

PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' config.yaml)
if [ ! -f "$PULL_SECRET_FILE" ]; then
    echo ""
    echo "Error: Pull secret file not found: $PULL_SECRET_FILE"
    echo "Please copy pull-secret.txt.example to $PULL_SECRET_FILE and paste your OpenShift pull secret."
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Configuration files found${NC}"
echo ""

# Step 2: Generate install-config.yaml
if [ "$RESUME_STEP" -le 2 ]; then
    echo "Step 2: Generating install-config.yaml..."
    bash scripts/generate-install-config.sh || exit 1
    update_checkpoint 2
    echo ""
fi

# Step 3: Install Hub Cluster
if [ "$RESUME_STEP" -le 3 ]; then
    echo "Step 3: Installing OpenShift Hub Cluster..."
    echo "⚠️  This will take 30-60 minutes. Please be patient..."
    bash scripts/install-hub-cluster.sh || exit 1
    update_checkpoint 3
    echo ""
fi

# Step 4: Verify cluster is ready
if [ "$RESUME_STEP" -le 4 ]; then
    echo "Step 4: Verifying cluster is ready..."
    bash scripts/verify-cluster-ready.sh || exit 1
    update_checkpoint 4
    echo ""
fi

# Step 5: Install ACM
if [ "$RESUME_STEP" -le 5 ]; then
    echo "Step 5: Installing ACM (Advanced Cluster Management)..."
    bash scripts/install-acm.sh || exit 1
    update_checkpoint 5
    echo ""
fi

# Step 6: Setup AWS prerequisites for hosted cluster
if [ "$RESUME_STEP" -le 6 ]; then
    echo "Step 6: Setting up AWS prerequisites for hosted cluster..."

    # Note: setup-aws-prerequisites.sh needs to be run from the directory where kubeconfig is located
    # The kubeconfig should be in the installer directory from Step 3
    # We need to determine where the installation happened
    if [ -f "installer/auth/kubeconfig" ]; then
        # If running from repo root and installer directory exists here
        WORK_DIR="$SCRIPT_DIR/installer"
    elif [ -f "auth/kubeconfig" ]; then
        # If already in the installer directory
        WORK_DIR="."
    else
        # Try to find kubeconfig in current directory or common locations
        if [ -f "$PWD/auth/kubeconfig" ]; then
            WORK_DIR="$PWD"
        else
            echo "⚠️  Warning: Could not find kubeconfig automatically."
            echo "   Please ensure you're running from the directory where the cluster was installed,"
            echo "   or that auth/kubeconfig exists in the installer/ subdirectory."
            echo ""
            echo "   Attempting to continue anyway..."
            WORK_DIR="${PWD}"
        fi
    fi

    cd "$WORK_DIR" || echo "Warning: Could not change to $WORK_DIR, continuing from current directory..."
    bash "$SCRIPT_DIR/scripts/setup-aws-prerequisites.sh" || exit 1
    cd "$SCRIPT_DIR" || true
    update_checkpoint 6
    echo ""
fi

# Step 7: Create hosted cluster
if [ "$RESUME_STEP" -le 7 ]; then
    echo "Step 7: Creating hosted cluster..."
    bash scripts/create-hosted-cluster.sh || exit 1
    update_checkpoint 7
    echo ""
fi

# Clear checkpoint on successful completion
rm -f "$CHECKPOINT_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Installation completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Your OpenShift Hub Cluster with ACM is ready!"
echo "Your Hosted Cluster has been created!"
