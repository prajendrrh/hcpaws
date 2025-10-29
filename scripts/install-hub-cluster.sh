#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Installing OpenShift Hub Cluster..."

# Use current working directory
WORK_DIR="${PWD:-$(pwd)}"

# Check if install-config.yaml exists
if [ ! -f "$WORK_DIR/install-config.yaml" ]; then
    echo "Error: install-config.yaml not found in current directory ($WORK_DIR). Please run generate-install-config.sh first."
    exit 1
fi

# Create cluster in current directory
echo "⏳ Creating cluster (this will take 30-60 minutes)..."
cd "$WORK_DIR"
openshift-install create cluster --dir . --log-level debug

echo "✅ Hub cluster installation completed!"

