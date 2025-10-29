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
echo "   Waiting for CSV to appear..."

# First, wait for the CSV to appear (it may take a few moments)
max_wait=60
counter=0
CSV_FOUND=false

while [ $counter -lt $max_wait ]; do
    CSV_NAME=$(oc get csv -n open-cluster-management -o name | grep advanced-cluster-management | head -n1 | cut -d'/' -f2 || echo "")
    if [ -n "$CSV_NAME" ]; then
        CSV_FOUND=true
        echo "   Found CSV: $CSV_NAME"
        break
    fi
    counter=$((counter + 1))
    echo "   Waiting for CSV to appear... ($counter/$max_wait)"
    sleep 10
done

if [ "$CSV_FOUND" = false ]; then
    echo "❌ Error: CSV not found after waiting. Checking subscription status..."
    oc get subscription -n open-cluster-management advanced-cluster-management
    echo "   Subscription status:"
    oc describe subscription -n open-cluster-management advanced-cluster-management | grep -A 10 "Status:" || true
    exit 1
fi

# Now wait for the CSV to be installed successfully
echo "   Waiting for CSV to reach InstallSucceeded condition..."
oc wait --for=condition=InstallSucceeded --timeout=20m "csv/$CSV_NAME" -n open-cluster-management

echo "✅ ACM Operator installed successfully!"

# Wait a bit more for operator to be fully ready (webhooks, etc.)
echo "   Waiting for operator to be fully ready..."
sleep 10

# Verify operator pods are running
echo "   Checking operator pod status..."
oc get pods -n open-cluster-management -l name=advanced-cluster-management --no-headers 2>/dev/null | head -1 | awk '{print $3}' | grep -q Running || echo "   Warning: Operator pods may still be starting"

# Step 4: Create MultiClusterHub
echo "🌐 Creating MultiClusterHub..."

# Check if MultiClusterHub already exists
MCH_EXISTS=false
if oc get multiclusterhub multiclusterhub -n open-cluster-management &>/dev/null; then
    MCH_EXISTS=true
    echo "   MultiClusterHub already exists, checking status..."
    MCH_STATUS=$(oc get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$MCH_STATUS" = "Running" ]; then
        echo "   ✅ MultiClusterHub is already Running!"
    else
        echo "   MultiClusterHub exists but status is: $MCH_STATUS"
        echo "   Waiting for MultiClusterHub to become ready..."
    fi
fi

if [ "$MCH_EXISTS" = false ]; then
    echo "   Creating MultiClusterHub resource..."
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
    
    # Verify it was created
    sleep 2
    if oc get multiclusterhub multiclusterhub -n open-cluster-management &>/dev/null; then
        echo "   ✅ MultiClusterHub resource created successfully"
    else
        echo "   ❌ Error: MultiClusterHub was not created. Checking for errors..."
        oc get events -n open-cluster-management --sort-by='.lastTimestamp' | tail -10 || true
        exit 1
    fi
fi

# Step 5: Wait for ACM Hub to be ready
echo "⏳ Waiting for ACM Hub to come online (this may take 10-15 minutes)..."

# Verify MultiClusterHub exists before waiting
if ! oc get multiclusterhub multiclusterhub -n open-cluster-management &>/dev/null; then
    echo "❌ Error: MultiClusterHub does not exist. Cannot wait for it to be ready."
    echo "   Please check the ACM operator logs for errors:"
    echo "   oc logs -n open-cluster-management -l control-plane=controller-manager"
    exit 1
fi

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

