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
cd openshift-acm-hub-installer
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

### 3. Run the Installation

Make scripts executable:

```bash
chmod +x main.sh scripts/*.sh
```

Run the main installer:

```bash
./main.sh
```

Or run individual steps as needed:

```bash
# Check prerequisites
./scripts/check-prerequisites.sh

# Generate install-config
./scripts/generate-install-config.sh

# Install hub cluster
./scripts/install-hub-cluster.sh

# Verify cluster
./scripts/verify-cluster-ready.sh

# Install ACM
./scripts/install-acm.sh

# Setup AWS prerequisites
./scripts/setup-aws-prerequisites.sh

# Create hosted cluster
./scripts/create-hosted-cluster.sh
```

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
openshift-acm-hub-installer/
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
│   └── create-hosted-cluster.sh      # Create hosted cluster
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
installer/auth/kubeconfig
```

Export it:

```bash
export KUBECONFIG=$(pwd)/installer/auth/kubeconfig
```

### ACM Console

Get the ACM console URL:

```bash
oc get route -n open-cluster-management multicloud-console -o jsonpath='{.spec.host}'
```

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

## Notes

- The hub cluster installation takes approximately 30-60 minutes
- ACM installation takes approximately 10-15 minutes
- Hosted cluster creation takes approximately 15-20 minutes
- Total time: ~60-95 minutes

## Support

For issues or questions:
- Check OpenShift documentation: https://docs.openshift.com/
- Check ACM documentation: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/
- Check HCP documentation: https://hypershift-docs.netlify.app/

## License

This tool is provided as-is for automation purposes.

