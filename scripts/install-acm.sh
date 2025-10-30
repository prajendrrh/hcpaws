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
oc new-project open-cluster-management &>/dev/null || echo "Namespace already exists"

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

# Step 3: Wait for Operator to be installed (simple)
echo "⏳ Waiting 60s for ACM Operator to settle..."
sleep 60

# Find the ACM CSV and check phase
CSV_NAME=$(oc get csv -n open-cluster-management -o name | grep advanced-cluster-management | head -n1 | cut -d'/' -f2 2>/dev/null || echo "")
if [ -z "$CSV_NAME" ]; then
    echo "❌ Error: ACM CSV not found after waiting"
    exit 1
fi

CSV_PHASE=$(oc get csv "$CSV_NAME" -n open-cluster-management -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
echo "   CSV: $CSV_NAME phase: ${CSV_PHASE:-unknown}"
if [ "$CSV_PHASE" != "Succeeded" ]; then
    echo "❌ Error: ACM Operator CSV not Succeeded (phase=$CSV_PHASE)"
    exit 1
fi

echo "✅ ACM Operator installed successfully (CSV Succeeded)"

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

# Step 5: Wait for ACM Hub to be ready (simple + longer wait)
echo "⏳ Waiting 60s for MultiClusterHub to settle..."
sleep 60

# Then check until Running with a simple loop (max 30 minutes)
MCH_TIMEOUT=1800
MCH_ELAPSED=0
MCH_INTERVAL=15

while [ $MCH_ELAPSED -le $MCH_TIMEOUT ]; do
    MCH_STATUS=$(oc get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$MCH_STATUS" = "Running" ]; then
        echo "✅ ACM Hub is ready (Running)"
        break
    fi
    if [ $MCH_ELAPSED -eq 0 ]; then
        echo "   Waiting for MultiClusterHub to be Running (current: ${MCH_STATUS:-unknown})"
    fi
    sleep $MCH_INTERVAL
    MCH_ELAPSED=$((MCH_ELAPSED + MCH_INTERVAL))
done

if [ "$MCH_STATUS" != "Running" ]; then
    echo "❌ Error: MultiClusterHub not Running after $((MCH_TIMEOUT/60)) minutes (last phase=$MCH_STATUS)"
    exit 1
fi

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

