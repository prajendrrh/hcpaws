#!/bin/bash

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$PROJECT_DIR/config.yaml" ]; then
    echo "Error: config.yaml not found. Please copy config.yaml.example to config.yaml and fill in your values."
    exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install it first."
    exit 1
fi

echo "📝 Generating install-config.yaml from template..."

# Read values from config.yaml
CLUSTER_NAME=$(yq eval '.hub_cluster.name' "$PROJECT_DIR/config.yaml")
BASE_DOMAIN=$(yq eval '.hub_cluster.base_domain' "$PROJECT_DIR/config.yaml")
REGION=$(yq eval '.hub_cluster.region' "$PROJECT_DIR/config.yaml")
PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' "$PROJECT_DIR/config.yaml")

# Get zones as array
ZONES=$(yq eval '.hub_cluster.zones[]' "$PROJECT_DIR/config.yaml" | tr '\n' ' ')

# Compute settings
COMPUTE_INSTANCE_TYPE=$(yq eval '.hub_cluster.compute.instance_type' "$PROJECT_DIR/config.yaml")
COMPUTE_REPLICAS=$(yq eval '.hub_cluster.compute.replicas' "$PROJECT_DIR/config.yaml")
COMPUTE_ARCH=$(yq eval '.hub_cluster.compute.architecture' "$PROJECT_DIR/config.yaml")
COMPUTE_HYPERTHREADING=$(yq eval '.hub_cluster.compute.hyperthreading' "$PROJECT_DIR/config.yaml")

# Control plane settings
CP_REPLICAS=$(yq eval '.hub_cluster.control_plane.replicas' "$PROJECT_DIR/config.yaml")
CP_ARCH=$(yq eval '.hub_cluster.control_plane.architecture' "$PROJECT_DIR/config.yaml")
CP_HYPERTHREADING=$(yq eval '.hub_cluster.control_plane.hyperthreading' "$PROJECT_DIR/config.yaml")

# Networking settings
CLUSTER_NETWORK_CIDR=$(yq eval '.hub_cluster.networking.cluster_network_cidr' "$PROJECT_DIR/config.yaml")
HOST_PREFIX=$(yq eval '.hub_cluster.networking.host_prefix' "$PROJECT_DIR/config.yaml")
MACHINE_NETWORK_CIDR=$(yq eval '.hub_cluster.networking.machine_network_cidr' "$PROJECT_DIR/config.yaml")
SERVICE_NETWORK_CIDR=$(yq eval '.hub_cluster.networking.service_network_cidr' "$PROJECT_DIR/config.yaml")
NETWORK_TYPE=$(yq eval '.hub_cluster.networking.network_type' "$PROJECT_DIR/config.yaml")

# Platform settings
PUBLISH=$(yq eval '.hub_cluster.platform.publish' "$PROJECT_DIR/config.yaml")
TRUST_BUNDLE_POLICY=$(yq eval '.hub_cluster.platform.additional_trust_bundle_policy' "$PROJECT_DIR/config.yaml")

# Read pull secret
if [ ! -f "$PROJECT_DIR/$PULL_SECRET_FILE" ]; then
    echo "Error: Pull secret file not found: $PROJECT_DIR/$PULL_SECRET_FILE"
    exit 1
fi

PULL_SECRET=$(cat "$PROJECT_DIR/$PULL_SECRET_FILE")

# Create zones array for YAML
ZONES_YAML=""
for zone in $ZONES; do
    ZONES_YAML="${ZONES_YAML}      - $zone"$'\n'
done
ZONES_YAML=$(echo "$ZONES_YAML" | sed '$s/^ *//')

# Generate install-config.yaml in current working directory
WORK_DIR="${PWD:-$(pwd)}"
cat > "$WORK_DIR/install-config.yaml" <<EOF
additionalTrustBundlePolicy: $TRUST_BUNDLE_POLICY
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: $COMPUTE_ARCH
  hyperthreading: $COMPUTE_HYPERTHREADING
  name: worker
  platform: 
    aws:
      type: $COMPUTE_INSTANCE_TYPE
      zones:
$ZONES_YAML
  replicas: $COMPUTE_REPLICAS
controlPlane:
  architecture: $CP_ARCH
  hyperthreading: $CP_HYPERTHREADING
  name: master
  platform: 
    aws:
      zones:
$ZONES_YAML
  replicas: $CP_REPLICAS
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: $CLUSTER_NETWORK_CIDR
    hostPrefix: $HOST_PREFIX
  machineNetwork:
  - cidr: $MACHINE_NETWORK_CIDR
  networkType: $NETWORK_TYPE
  serviceNetwork:
  - $SERVICE_NETWORK_CIDR
platform:
  aws:
    region: $REGION
publish: $PUBLISH
pullSecret: '$PULL_SECRET'
EOF

echo "✅ Generated install-config.yaml at $WORK_DIR/install-config.yaml"

