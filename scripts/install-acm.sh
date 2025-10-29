#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🧰 Installing ACM (Advanced Cluster Management)..."

# Use current working directory
WORK_DIR="${PWD:-$(pwd)}"

# Check if kubeconfig exists
if [ ! -f "$WORK_DIR/auth/kubeconfig" ]; then
    echo "Error: kubeconfig not found at $WORK_DIR/auth/kubeconfig. Please ensure the cluster is installed and ready."
    exit 1
fi

export KUBECONFIG="$WORK_DIR/auth/kubeconfig"

# Step 1: Create the Operator Namespace
echo "📦 Creating open-cluster-management namespace..."
oc new-project open-cluster-management || echo "Namespace already exists"

# Step 2: Install ACM Operator
echo "📦 Installing ACM Operator..."
cat > /tmp/acm-operator-subscription.yaml <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: acm-operator-group
  namespace: open-cluster-management
spec:
  targetNamespaces:
    - open-cluster-management
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
spec:
  channel: release-2.14
  name: advanced-cluster-management
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc apply -f /tmp/acm-operator-subscription.yaml

# Step 3: Wait for Operator to be installed
echo "⏳ Waiting for ACM Operator to be installed..."
oc wait --for=condition=InstallSucceeded --timeout=20m csv -n open-cluster-management -l operators.coreos.com/advanced-cluster-management.open-cluster-management

echo "✅ ACM Operator installed successfully!"

# Step 4: Create MultiClusterHub
echo "🌐 Creating MultiClusterHub..."
cat > /tmp/multiclusterhub.yaml <<EOF
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: multiclusterhub
  namespace: open-cluster-management
spec:
  availabilityConfig: High
EOF

oc apply -f /tmp/multiclusterhub.yaml

# Step 5: Wait for ACM Hub to be ready
echo "⏳ Waiting for ACM Hub to come online (this may take 10-15 minutes)..."
oc wait --for=condition=Available --timeout=30m multiclusterhub/multiclusterhub -n open-cluster-management

echo "✅ ACM Hub is ready!"

# Step 6: Get ACM Console URL
echo "🔗 ACM Console URL:"
oc get route -n open-cluster-management multicloud-console -o jsonpath='{.spec.host}' 2>/dev/null || echo "Console route not yet available"

# Step 7: Install Hypershift Add-on
echo "🚀 Installing Hypershift Add-on..."
cat > /tmp/hypershift-addon.yaml <<EOF
apiVersion: addon.open-cluster-management.io/v1alpha1
kind: ManagedClusterAddOn
metadata:
  name: hypershift-addon
  namespace: local-cluster
spec:
  installNamespace: open-cluster-management-agent-addon
EOF

oc apply -f /tmp/hypershift-addon.yaml || echo "Hypershift addon may already be installed"

echo "✅ ACM installation completed!"

# Cleanup temp files
rm -f /tmp/acm-operator-subscription.yaml /tmp/multiclusterhub.yaml /tmp/hypershift-addon.yaml

