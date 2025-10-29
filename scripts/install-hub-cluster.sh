#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Installing OpenShift Hub Cluster..."

cd "$PROJECT_DIR/installer"

# Check if install-config.yaml exists
if [ ! -f "install-config.yaml" ]; then
    echo "Error: install-config.yaml not found. Please run generate-install-config.sh first."
    exit 1
fi

# Create cluster
echo "⏳ Creating cluster (this will take 30-60 minutes)..."
openshift-install create cluster --dir . --log-level debug

echo "✅ Hub cluster installation completed!"

