# End-to-End Testing Guide

This guide explains how to test the modular installation scripts end-to-end.

## Prerequisites

Before starting, ensure you have:

1. **AWS Account** with appropriate permissions
2. **OpenShift Pull Secret** - Download from [Red Hat](https://console.redhat.com/openshift/install/pull-secret)
3. **Required CLI Tools**:
   - `oc` (OpenShift CLI)
   - `aws` (AWS CLI)
   - `openshift-install`
   - `hcp` (Hypershift CLI)
   - `yq`
   - `jq`

4. **Configuration Files**:
   - `config.yaml` (copy from `config.yaml.example`)
   - `aws-credentials.env` (copy from `aws-credentials.env.example`)
   - `pull-secret.txt` (your OpenShift pull secret)

## Step-by-Step Testing

### 1. Initial Setup

```bash
# Clone and navigate to the repository
cd /path/to/hcpaws

# Copy example files
cp config.yaml.example config.yaml
cp aws-credentials.env.example aws-credentials.env

# Edit config.yaml with your values
# Edit aws-credentials.env with your AWS credentials
# Place your pull-secret.txt file
```

### 2. Module 1: Create Management (Hub) Cluster

```bash
bash hub.sh
```

**What it does:**
- Checks prerequisites
- Generates `install-config.yaml`
- Installs OpenShift hub cluster (30-60 minutes)
- Verifies cluster is ready

**Verification:**
```bash
# Check cluster status
export KUBECONFIG=$(pwd)/installer/auth/kubeconfig
oc cluster-info
oc get nodes

# Should see cluster URL and nodes in Ready state
```

**Expected Output:**
- Cluster API URL
- All nodes in Ready state
- No errors in the installation

### 3. Module 2: Install ACM

```bash
bash acm.sh
```

**What it does:**
- Creates `open-cluster-management` namespace
- Installs ACM operator
- Creates MultiClusterHub
- Installs Hypershift add-on

**Verification:**
```bash
# Check ACM operator
oc get csv -n open-cluster-management | grep advanced-cluster-management
# Should show phase: Succeeded

# Check MultiClusterHub
oc get multiclusterhub -n open-cluster-management
# Should show phase: Running

# Check ACM console route
oc get route multicloud-console -n open-cluster-management
```

**Expected Output:**
- CSV in Succeeded phase
- MultiClusterHub in Running phase
- Console route available

### 4. Module 3: Setup Prerequisites for Hosted Cluster

```bash
bash prereq.sh
```

**What it does:**
- Creates S3 bucket for OIDC provider
- Creates IAM role with necessary permissions
- Creates OIDC provider secret in cluster
- Generates STS credentials (`sts-creds.json`)

**Verification:**
```bash
# Check S3 bucket exists
aws s3 ls | grep <your-bucket-name>

# Check IAM role exists
aws iam get-role --role-name <your-role-name>

# Check STS credentials file
ls -la <pull-secret-directory>/sts-creds.json

# Check OIDC secret in cluster
oc get secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster
```

**Expected Output:**
- S3 bucket visible
- IAM role exists with correct trust policy
- `sts-creds.json` file exists
- Secret created in `local-cluster` namespace

**⚠️ IMPORTANT:** Wait 2-5 minutes after this step before proceeding. This allows AWS IAM policies to fully propagate.

### 5. Module 4: Create Hosted Cluster

```bash
bash hosted.sh
```

**What it does:**
- Creates hosted cluster using `hcp` CLI
- Configures node pools
- Sets up networking

**Verification:**
```bash
# Check hosted cluster status
oc get hostedcluster -n <namespace>

# Check node pools
oc get nodepool -n <namespace>

# Get cluster kubeconfig
oc get secret <cluster-name>-admin-kubeconfig -n <namespace> -o jsonpath='{.data.kubeconfig}' | base64 -d > hosted-kubeconfig
export KUBECONFIG=./hosted-kubeconfig
oc cluster-info
```

**Expected Output:**
- Hosted cluster created successfully
- Node pools in Ready state
- Can access hosted cluster API

## Troubleshooting

### Issue: IAM Role Assumption Fails

**Symptoms:**
```
AccessDenied: User is not authorized to perform: sts:AssumeRole
```

**Solution:**
1. Wait a few more minutes for IAM propagation
2. Verify trust policy allows your user ARN:
   ```bash
   aws iam get-role --role-name <role-name> --query 'Role.AssumeRolePolicyDocument'
   ```
3. Re-run Module 3 if needed

### Issue: UnauthorizedOperation on VPC Listing

**Symptoms:**
```
UnauthorizedOperation: You are not authorized to perform this operation
```

**Solution:**
1. Wait 2-5 minutes after Module 3 completes
2. Verify IAM policy has `ec2:DescribeVpcs`:
   ```bash
   aws iam get-role-policy --role-name <role-name> --policy-name hcp-cli-policy
   ```
3. The script has retry logic, but manual wait is more reliable

### Issue: OIDC ConfigMap Not Found

**Symptoms:**
```
configmaps "oidc-storage-provider-s3-config" not found
```

**Solution:**
1. Wait for Hypershift operator to process the secret (5-10 minutes)
2. Check if secret exists:
   ```bash
   oc get secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster
   ```
3. Re-run Module 3 if needed

### Issue: Hosted Cluster Creation Fails on First Run

**Symptoms:**
- First run fails with IAM/permissions errors
- Second run (with `-r` or re-run) succeeds

**Solution:**
This is likely IAM propagation delay. Solutions:
1. **Best:** Wait 5-10 minutes after Module 3 before running Module 4
2. The script has retry logic, but manual wait is more reliable
3. Use modular approach: run modules separately with time gaps

## Testing with Resume

If a module fails, you can use the original `main.sh` with resume:

```bash
# Run full workflow
bash main.sh

# If it fails, resume from last checkpoint
bash main.sh -r
```

## Full Workflow Timing

Expected time for complete installation:

- **Module 1 (Hub Cluster):** 30-60 minutes
- **Module 2 (ACM):** 10-20 minutes
- **Module 3 (Prerequisites):** 2-5 minutes + 5 minute wait
- **Module 4 (Hosted Cluster):** 15-20 minutes

**Total:** ~1.5-2 hours + waiting time for IAM propagation

## Quick Test Sequence

```bash
# 1. Setup (one time)
cp config.yaml.example config.yaml
cp aws-credentials.env.example aws-credentials.env
# Edit files with your values

# 2. Run modules sequentially
bash hub.sh          # ~45 minutes
bash acm.sh          # ~15 minutes
bash prereq.sh       # ~2 minutes
sleep 300            # Wait 5 minutes for IAM propagation
bash hosted.sh       # ~20 minutes

# 3. Verify everything works
export KUBECONFIG=$(pwd)/installer/auth/kubeconfig
oc get hostedcluster -A
```

## Cleanup

To clean up and start fresh:

```bash
# Delete hosted cluster
bash scripts/delete-hosted-cluster.sh

# Delete everything (hub cluster + hosted cluster + AWS resources)
bash scripts/delete-all.sh
```

## Notes

- The modular approach helps identify timing issues
- Natural time gaps between modules help AWS IAM propagation
- Each module can be run independently for debugging
- Check logs if any step fails: logs are saved in the working directory

