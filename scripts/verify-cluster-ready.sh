#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔍 Verifying cluster is ready..."

cd "$PROJECT_DIR/installer"

# Check if kubeconfig exists
if [ ! -f "auth/kubeconfig" ]; then
    echo "Error: kubeconfig not found. Cluster installation may not be complete."
    exit 1
fi

# Export kubeconfig
export KUBECONFIG="$PROJECT_DIR/installer/auth/kubeconfig"

# Wait for cluster to be ready
echo "⏳ Waiting for cluster to be ready..."
max_attempts=60
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if oc get nodes 2>/dev/null | grep -q Ready; then
        nodes=$(oc get nodes --no-headers | grep -c Ready || echo "0")
        if [ "$nodes" -ge 3 ]; then
            echo "✅ Cluster is ready with $nodes nodes in Ready state!"
            break
        fi
    fi
    
    attempt=$((attempt + 1))
    echo "  Attempt $attempt/$max_attempts: Waiting for cluster to be ready..."
    sleep 60
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Timeout waiting for cluster to be ready"
    exit 1
fi

# Verify all cluster operators are available
echo "⏳ Verifying cluster operators..."
oc wait --for=condition=Available --timeout=20m clusteroperators.config.openshift.io --all

echo "✅ Cluster is fully ready!"

