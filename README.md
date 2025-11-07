# OpenShift ACM Hub & Hosted Cluster Installer

This tool automates the creation of an OpenShift Management Cluster (Hub) with Advanced Cluster Management (ACM) installed, and then creates a hosted cluster on AWS.

## Overview

This automation tool performs the following tasks:

1. ✅ Checks and installs prerequisites (openshift-install, oc, hcp, aws CLI)
2. ✅ Generates install-config.yaml from template
3. ✅ Installs OpenShift 4.19 Hub Cluster on AWS
4. ✅ Verifies cluster is ready
5. ✅ Installs ACM (Advanced Cluster Management) operator
6. ✅ Sets up AWS prerequisites for hosted cluster (S3 bucket, IAM roles, etc.)
7. ✅ Creates a hosted cluster using ACM

## Prerequisites

Before running the tool, ensure you have:

- AWS account with appropriate permissions
- OpenShift pull secret (get from [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret))
- AWS Access Key ID and Secret Access Key
- Domain configured in Route53 (for base domain)

## Quick Start

### 1. Clone or Download this Repository

```bash
git clone https://github.com/prajendrrh/hcpaws.git
cd hcpaws
```

### 2. Configure the Tool

Copy the example configuration files and fill in your values:

```bash
cp config.yaml.example config.yaml
cp aws-credentials.env.example aws-credentials.env
cp pull-secret.txt.example pull-secret.txt
```

Edit the files with your actual values:

- **config.yaml**: Fill in cluster names, domains, regions, etc.
- **aws-credentials.env**: Fill in your AWS Access Key ID and Secret Access Key
- **pull-secret.txt**: Paste your OpenShift pull secret

### 3. Make Scripts Executable

```bash
chmod +x main.sh scripts/*.sh
```

## Usage

### Option 1: Modular Installation (Recommended)

The installation is split into 4 modules that can be run independently. This approach allows natural time gaps between steps and makes it easier to debug issues:

```bash
# Module 1: Create Management (Hub) Cluster
bash hub.sh
# ~45 minutes - Creates OpenShift hub cluster

# Module 2: Install ACM
bash acm.sh
# ~15 minutes - Installs Advanced Cluster Management

# Module 3: Setup Prerequisites for Hosted Cluster
bash prereq.sh
# ~2-5 minutes - Creates S3 bucket, IAM role, OIDC secret, STS credentials

# Module 4: Create Hosted Cluster
bash hosted.sh
# ~20 minutes - Creates hosted cluster using hcp CLI
```

**Benefits of modular approach:**
- Natural time gaps help AWS IAM policies propagate
- Each module can be run independently for debugging
- Easier to identify which step has issues
- Allows manual verification between steps

**Total time: ~1.5-2 hours** (including natural delays between modules)

### Option 2: Full Automated Installation

Run the complete installation workflow in one go:

```bash
./main.sh
```

This will execute all steps in order:
1. Check prerequisites
2. Generate install-config.yaml
3. Install OpenShift Hub Cluster (30-60 minutes)
4. Verify cluster is ready
5. Install ACM (10-15 minutes)
6. Setup AWS prerequisites for hosted cluster
7. Create hosted cluster (15-20 minutes)

**Total time: ~60-95 minutes**

All output messages include timestamps in format `[YYYY-MM-DD HH:MM:SS]` for better traceability.

### Resume Installation

If the installation fails or is interrupted, you can resume from where it stopped:

```bash
./main.sh --resume
```

or

```bash
./main.sh -r
```

The script uses a checkpoint file (`.checkpoint`) to track progress. It will skip completed steps and continue from the last failed step.

**Note:** The checkpoint file is automatically created and updated during installation, and is removed upon successful completion.

### Run Individual Scripts

You can also run individual scripts manually:

```bash
# Step 1: Check prerequisites
./scripts/check-prerequisites.sh

# Step 2: Generate install-config.yaml
./scripts/generate-install-config.sh

# Step 3: Install hub cluster (30-60 minutes)
./scripts/install-hub-cluster.sh

# Step 4: Verify cluster is ready
./scripts/verify-cluster-ready.sh

# Step 5: Install ACM (10-15 minutes)
./scripts/install-acm.sh

# Step 6: Setup AWS prerequisites
cd installer  # Must be run from directory containing auth/kubeconfig
../scripts/setup-aws-prerequisites.sh

# Step 7: Create hosted cluster (15-20 minutes)
./scripts/create-hosted-cluster.sh
```

### Delete Operations

#### Delete Hosted Cluster Only

To delete only the hosted cluster (keeps hub cluster and ACM):

```bash
./scripts/delete-hosted-cluster.sh
```

This will:
- Delete the hosted cluster using hcp CLI
- Remove cluster resources from ACM
- Clean up AWS resources associated with the hosted cluster (VPCs, subnets, load balancers, etc.)
- **Note:** Does NOT delete the hub cluster, ACM, S3 bucket, or IAM role

#### Delete All Resources

To delete everything (hub cluster, hosted cluster, and all AWS prerequisites):

**⚠️ Warning:** This will delete the hub cluster, all hosted clusters, and AWS resources!

```bash
./scripts/delete-all.sh
```

This will:
- Delete all hosted clusters
- Delete the hub cluster (using openshift-install destroy)
- Delete the S3 bucket for OIDC provider
- Delete the IAM role and policies
- Clean up all associated AWS resources

**Output:** All deletion operations are logged to `cluster-destruction.log` in the installation directory.

## Configuration

### config.yaml

Main configuration file with all cluster settings:

- **hub_cluster**: Settings for the OpenShift Management Cluster
- **hosted_cluster**: Settings for the hosted cluster
- **aws**: AWS-specific settings

### aws-credentials.env

AWS credentials file:

```env
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
```

### pull-secret.txt

Your OpenShift pull secret from Red Hat Console.

## Directory Structure

```
hcpaws/
├── main.sh                    # Main orchestrator script
├── config.yaml.example        # Configuration template
├── aws-credentials.env.example # AWS credentials template
├── pull-secret.txt.example    # Pull secret template
├── .gitignore
├── README.md
├── scripts/
│   ├── check-prerequisites.sh        # Check/install prerequisites
│   ├── generate-install-config.sh    # Generate install-config.yaml
│   ├── install-hub-cluster.sh        # Install OpenShift hub cluster
│   ├── verify-cluster-ready.sh       # Verify cluster is ready
│   ├── install-acm.sh                # Install ACM operator
│   ├── setup-aws-prerequisites.sh    # Setup AWS resources
│   ├── setup-aws-credentials.sh      # Setup AWS credentials
│   ├── create-hosted-cluster.sh      # Create hosted cluster
│   ├── delete-hosted-cluster.sh      # Delete hosted cluster
│   └── delete-all.sh                 # Delete all resources
└── installer/                        # Created during installation
    ├── install-config.yaml          # Generated install config
    └── auth/                        # Cluster credentials
```

## What Gets Created

### AWS Resources

- OpenShift Hub Cluster (3 control plane, 3 worker nodes)
- S3 bucket for OIDC provider
- IAM role with necessary permissions
- Hosted cluster resources (VPCs, subnets, load balancers, etc.)

### OpenShift Resources

- OpenShift Hub Cluster with ACM
- MultiClusterHub instance
- Hypershift add-on
- Hosted cluster managed by ACM

## Accessing the Clusters

### Hub Cluster

After installation, kubeconfig is available at:

```
auth/kubeconfig
```

Export it:

```bash
export KUBECONFIG=$(pwd)/auth/kubeconfig
```

**Note:** The kubeconfig location depends on where you ran the installation. It's typically in the `installer` directory or the current working directory where the cluster was installed.

## Troubleshooting

### Cluster Installation Fails

- Check AWS credentials are correct
- Verify you have sufficient AWS permissions
- Check that the base domain is configured in Route53
- Review logs in `installer/.openshift_install.log`

### ACM Installation Fails

- Ensure the hub cluster is fully ready (all operators available)
- Check network connectivity
- Review ACM operator logs: `oc logs -n open-cluster-management -l name=advanced-cluster-management`

### Hosted Cluster Creation Fails

- Verify AWS prerequisites were set up correctly
- Check IAM role has necessary permissions
- Ensure S3 bucket exists and is accessible
- Review hcp CLI output for errors

## Installation Methods Comparison

### Modular Scripts (hub.sh, acm.sh, prereq.sh, hosted.sh)
- **Best for:** First-time setup, debugging, learning
- **Advantages:**
  - Natural time gaps between modules help AWS IAM propagation
  - Easy to debug which step failed
  - Can verify each step before proceeding
  - More reliable for first-time runs
- **Usage:** Run each module sequentially with time between steps

### Full Automated (main.sh)
- **Best for:** Repeatable automated deployments
- **Advantages:**
  - Single command for complete installation
  - Resume capability if interrupted
  - Checkpoint system tracks progress
- **Note:** May require retries due to timing issues on first run

## Installation Steps Detail

The installation process consists of 7 steps:

### Step 1: Check Prerequisites
- Verifies required tools are installed: `openshift-install`, `oc`, `hcp`, `aws`, `yq`, `envsubst`
- Shows installation instructions if any tool is missing
- Always runs at the beginning, even when resuming

### Step 2: Generate install-config.yaml
- Reads configuration from `config.yaml`
- Generates `installer/install-config.yaml` for OpenShift installation
- Validates AWS credentials

### Step 3: Install OpenShift Hub Cluster
- Creates OpenShift 4.19 cluster on AWS
- Uses `openshift-install` to provision infrastructure
- **Duration: 30-60 minutes**
- Creates 3 control plane nodes and 3 worker nodes by default
- Generates kubeconfig at `installer/auth/kubeconfig`

### Step 4: Verify Cluster is Ready
- Waits for all cluster operators to be available
- Verifies cluster nodes are ready
- Ensures cluster is fully operational before proceeding

### Step 5: Install ACM
- Installs Advanced Cluster Management operator
- Creates MultiClusterHub instance
- Installs Hypershift add-on
- **Duration: 10-15 minutes**

### Step 6: Setup AWS Prerequisites
- Waits for Hypershift operator to be running
- Creates S3 bucket for OIDC provider
- Sets up bucket policies
- Creates IAM role with necessary permissions
- Creates Kubernetes secret for hypershift operator (after operator is ready)
- Waits for operator to create OIDC ConfigMap automatically
- Generates STS credentials (`sts-creds.json`)
- Verifies IAM policy permissions are active
- **Note:** Must be run from directory containing `auth/kubeconfig`
- **Timing:** Waits for operator readiness to ensure secret is processed immediately

### Step 7: Create Hosted Cluster
- Uses `hcp` CLI to create hosted cluster on AWS
- Creates cluster in the namespace specified in config
- **Duration: 15-20 minutes**
- Logs saved to `hosted-cluster-creation.log`

## Features

### Timestamps
All output messages include timestamps in format `[YYYY-MM-DD HH:MM:SS]` for better traceability:

```
[2025-01-12 14:30:45] Step 1: Checking prerequisites...
[2025-01-12 14:30:50] Step 2: Generating install-config.yaml...
```

### Checkpoint/Resume
- Automatically tracks installation progress in `.checkpoint` file
- Can resume from any step if installation is interrupted
- Checkpoint is automatically cleared on successful completion

### Error Handling
- Scripts validate prerequisites before running
- Clear error messages with suggestions for resolution
- Failed steps can be retried individually

## Notes

- The hub cluster installation takes approximately **30-60 minutes**
- ACM installation takes approximately **10-15 minutes**
- Hosted cluster creation takes approximately **15-20 minutes**
- **Total time: ~60-95 minutes**
- The `sts-creds.json` file is saved in the same directory as `pull-secret.txt`
- All sensitive files (credentials, configs) are excluded from git via `.gitignore`

## Support

For issues or questions:
- Check OpenShift documentation: https://docs.openshift.com/
- Check ACM documentation: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/
- Check HCP documentation: https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html-single/hosted_control_planes/

## License

This tool is provided as-is for automation purposes.

