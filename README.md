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

### Create Installation (Full Workflow)

Run the complete installation workflow:

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

### Run Individual Steps

You can also run individual steps manually:

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

### Delete Hosted Cluster

To delete a hosted cluster:

```bash
./scripts/delete-hosted-cluster.sh
```

This will:
- Delete the hosted cluster using hcp CLI
- Remove cluster resources from ACM
- Clean up AWS resources associated with the hosted cluster

### Delete All Resources

To delete everything (hub cluster and hosted cluster):

**⚠️ Warning:** This will delete the hub cluster and all hosted clusters!

```bash
./scripts/delete-all.sh
```

This will:
- Delete all hosted clusters
- Delete the hub cluster (if using OpenShift installer-managed cluster)
- Clean up associated AWS resources

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
- Creates S3 bucket for OIDC provider
- Sets up bucket policies
- Creates IAM role with necessary permissions
- Generates STS credentials (`sts-creds.json`)
- Creates Kubernetes secret for hypershift operator
- **Note:** Must be run from directory containing `auth/kubeconfig`

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
- Check HCP documentation: https://hypershift-docs.netlify.app/

## License

This tool is provided as-is for automation purposes.

