#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "☁️  Setting up AWS prerequisites for hosted cluster..."

# Load configuration
if [ ! -f "$PROJECT_DIR/config.yaml" ]; then
    echo "Error: config.yaml not found."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/aws-credentials.env" ]; then
    echo "Error: aws-credentials.env not found."
    exit 1
fi

# Setup AWS credentials in ~/.aws/credentials and ~/.aws/config
# Source it to preserve environment variables for use in this script
source "$SCRIPT_DIR/setup-aws-credentials.sh"

# Read config values
BUCKET_NAME=$(yq eval '.hosted_cluster.s3_bucket.name' "$PROJECT_DIR/config.yaml")
HOSTED_REGION=$(yq eval '.hosted_cluster.region' "$PROJECT_DIR/config.yaml")
IAM_ROLE_NAME=$(yq eval '.aws.iam_role.name' "$PROJECT_DIR/config.yaml")

# Get current user ARN
echo "🔍 Getting current AWS user ARN..."
USER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
echo "  User ARN: $USER_ARN"

# Step 1: Create S3 bucket
echo "📦 Creating S3 bucket: $BUCKET_NAME..."
aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --create-bucket-configuration LocationConstraint="$HOSTED_REGION" \
    --region "$HOSTED_REGION" 2>/dev/null || echo "  Bucket may already exist"

# Step 2: Delete public access block
echo "🔓 Removing public access block from bucket..."
aws s3api delete-public-access-block --bucket "$BUCKET_NAME" || true

# Step 3: Create bucket policy
echo "📄 Creating bucket policy..."
mkdir -p "$PROJECT_DIR/tmp"
export BUCKET_NAME
cat > "$PROJECT_DIR/tmp/policy.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*" 
        }
    ]
}
EOF

# Step 4: Apply bucket policy
echo "📋 Applying bucket policy..."
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file://"$PROJECT_DIR/tmp/policy.json"

# Step 5: Create credentials file from AWS credentials
echo "🔑 Creating credentials file for secret..."

# Ensure AWS credentials are available and properly set
# First, verify if they're already set from setup-aws-credentials.sh
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "   AWS credentials not found in environment variables"
    echo "   Loading from aws-credentials.env..."
    if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
        source "$PROJECT_DIR/aws-credentials.env"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    else
        echo "❌ Error: aws-credentials.env file not found at $PROJECT_DIR/aws-credentials.env"
        exit 1
    fi
fi

# Validate that credentials are actually set and not empty
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ Error: AWS credentials are empty or not set"
    echo "   Please verify your aws-credentials.env file contains:"
    echo "   AWS_ACCESS_KEY_ID=your-access-key"
    echo "   AWS_SECRET_ACCESS_KEY=your-secret-key"
    exit 1
fi

# Remove any whitespace that might have been accidentally included
AWS_ACCESS_KEY_ID=$(echo "$AWS_ACCESS_KEY_ID" | xargs)
AWS_SECRET_ACCESS_KEY=$(echo "$AWS_SECRET_ACCESS_KEY" | xargs)

# Additional validation: check that values are not empty after trimming
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ Error: AWS credentials are empty after processing"
    exit 1
fi

echo "   ✅ AWS credentials validated"

# Create tmp directory if it doesn't exist
mkdir -p "$PROJECT_DIR/tmp"

# Create the credentials file with the validated values
cat > "$PROJECT_DIR/tmp/credentials" <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF

# Verify the file was created with content
if [ ! -f "$PROJECT_DIR/tmp/credentials" ] || [ ! -s "$PROJECT_DIR/tmp/credentials" ]; then
    echo "❌ Error: Failed to create credentials file at $PROJECT_DIR/tmp/credentials"
    exit 1
fi

# Verify that the credentials file actually contains values (not just keys with empty values)
if ! grep -q "aws_access_key_id=.\+" "$PROJECT_DIR/tmp/credentials" || ! grep -q "aws_secret_access_key=.\+" "$PROJECT_DIR/tmp/credentials"; then
    echo "❌ Error: Credentials file was created but values are missing!"
    echo "   File contents:"
    cat "$PROJECT_DIR/tmp/credentials"
    exit 1
fi

# Additional check: ensure the values are not just empty strings
if grep -q "aws_access_key_id=$" "$PROJECT_DIR/tmp/credentials" || grep -q "aws_secret_access_key=$" "$PROJECT_DIR/tmp/credentials"; then
    echo "❌ Error: Credentials file contains empty values!"
    echo "   File contents:"
    cat "$PROJECT_DIR/tmp/credentials"
    exit 1
fi

echo "   ✅ Credentials file created at $PROJECT_DIR/tmp/credentials with valid values"

# Step 6: Get kubeconfig
# Use current working directory
WORK_DIR="${PWD:-$(pwd)}"
if [ ! -f "$WORK_DIR/auth/kubeconfig" ]; then
    echo "Error: kubeconfig not found at $WORK_DIR/auth/kubeconfig. Please ensure the hub cluster is installed."
    exit 1
fi

export KUBECONFIG="$WORK_DIR/auth/kubeconfig"

# Step 7: Create secret for hypershift operator
echo "🔐 Creating hypershift operator OIDC provider secret..."

# Delete existing secret if it exists (to ensure fresh credentials)
echo "   Deleting existing secret if present..."
oc delete secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster 2>/dev/null || echo "   No existing secret found"

# Verify credentials file exists and has valid content
if [ ! -f "$PROJECT_DIR/tmp/credentials" ] || [ ! -s "$PROJECT_DIR/tmp/credentials" ]; then
    echo "❌ Error: Credentials file missing or empty!"
    exit 1
fi

# Verify credentials are in the file
if ! grep -q "aws_access_key_id" "$PROJECT_DIR/tmp/credentials" || ! grep -q "aws_secret_access_key" "$PROJECT_DIR/tmp/credentials"; then
    echo "❌ Error: Credentials file format is invalid!"
    echo "   Expected format:"
    echo "   [default]"
    echo "   aws_access_key_id=..."
    echo "   aws_secret_access_key=..."
    exit 1
fi

echo "   Creating secret with fresh credentials..."
oc create secret generic hypershift-operator-oidc-provider-s3-credentials \
    --from-file=credentials="$PROJECT_DIR/tmp/credentials" \
    --from-literal=bucket="$BUCKET_NAME" \
    --from-literal=region="$HOSTED_REGION" \
    -n local-cluster

echo "   ✅ Secret created successfully in local-cluster namespace"

# Verify secret was created and show basic info
if oc get secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster &>/dev/null; then
    echo "   Secret verified in cluster"
else
    echo "❌ Warning: Secret creation may have failed"
fi

# Step 8: Create IAM role trust policy
echo "🔐 Creating IAM role trust policy..."
cat > "$PROJECT_DIR/tmp/iam_role.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${USER_ARN}"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Step 9: Create IAM role
echo "👤 Creating IAM role: $IAM_ROLE_NAME..."
ROLE_ARN=$(aws iam create-role \
    --role-name "$IAM_ROLE_NAME" \
    --assume-role-policy-document file://"$PROJECT_DIR/tmp/iam_role.json" \
    --query "Role.Arn" \
    --output text 2>/dev/null || \
    aws iam get-role --role-name "$IAM_ROLE_NAME" --query "Role.Arn" --output text)

echo "  Role ARN: $ROLE_ARN"

# Step 9.5: Wait for IAM role trust policy to propagate (AWS IAM propagation delay)
echo "⏳ Waiting for IAM role to become assumable (AWS IAM propagation)..."
IAM_WAIT_MAX=30  # Maximum 30 seconds
IAM_WAIT_ELAPSED=0
IAM_WAIT_INTERVAL=2

while [ $IAM_WAIT_ELAPSED -lt $IAM_WAIT_MAX ]; do
    if aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "iam-propagation-check" --duration-seconds 900 &>/dev/null; then
        echo "  ✅ IAM role is ready (propagated after ${IAM_WAIT_ELAPSED}s)"
        break
    fi
    sleep $IAM_WAIT_INTERVAL
    IAM_WAIT_ELAPSED=$((IAM_WAIT_ELAPSED + IAM_WAIT_INTERVAL))
done

if [ $IAM_WAIT_ELAPSED -ge $IAM_WAIT_MAX ]; then
    echo "  ⚠️  Warning: Could not verify role assumption after ${IAM_WAIT_MAX}s"
    echo "     This may be okay - AWS IAM propagation can take longer. Continuing..."
fi

# Step 10: Create IAM role policy
echo "📋 Creating IAM role policy..."
cat > "$PROJECT_DIR/tmp/hcp_policy.json" <<'POLICYEOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2",
            "Effect": "Allow",
            "Action": [
                "ec2:CreateDhcpOptions",
                "ec2:DeleteSubnet",
                "ec2:ReplaceRouteTableAssociation",
                "ec2:DescribeAddresses",
                "ec2:DescribeInstances",
                "ec2:DeleteVpcEndpoints",
                "ec2:CreateNatGateway",
                "ec2:CreateVpc",
                "ec2:DescribeDhcpOptions",
                "ec2:AttachInternetGateway",
                "ec2:DeleteVpcEndpointServiceConfigurations",
                "ec2:DeleteRouteTable",
                "ec2:AssociateRouteTable",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeAvailabilityZones",
                "ec2:CreateRoute",
                "ec2:CreateInternetGateway",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:ModifyVpcAttribute",
                "ec2:DeleteInternetGateway",
                "ec2:DescribeVpcEndpointConnections",
                "ec2:RejectVpcEndpointConnections",
                "ec2:DescribeRouteTables",
                "ec2:ReleaseAddress",
                "ec2:AssociateDhcpOptions",
                "ec2:TerminateInstances",
                "ec2:CreateTags",
                "ec2:DeleteRoute",
                "ec2:CreateRouteTable",
                "ec2:DetachInternetGateway",
                "ec2:DescribeVpcEndpointServiceConfigurations",
                "ec2:DescribeNatGateways",
                "ec2:DisassociateRouteTable",
                "ec2:AllocateAddress",
                "ec2:DescribeSecurityGroups",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:CreateVpcEndpoint",
                "ec2:DescribeVpcs",
                "ec2:DeleteSecurityGroup",
                "ec2:DeleteDhcpOptions",
                "ec2:DeleteNatGateway",
                "ec2:DescribeVpcEndpoints",
                "ec2:DeleteVpc",
                "ec2:CreateSubnet",
                "ec2:DescribeSubnets"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ELB",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DeleteTargetGroup"
            ],
            "Resource": "*"
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:*:iam::*:role/*-worker-role",
            "Condition": {
                "ForAnyValue:StringEqualsIfExists": {
                    "iam:PassedToService": "ec2.amazonaws.com"
                }
            }
        },
        {
            "Sid": "IAM",
            "Effect": "Allow",
            "Action": [
                "iam:CreateInstanceProfile",
                "iam:DeleteInstanceProfile",
                "iam:GetRole",
                "iam:UpdateAssumeRolePolicy",
                "iam:GetInstanceProfile",
                "iam:TagRole",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:PutRolePolicy",
                "iam:AddRoleToInstanceProfile",
                "iam:CreateOpenIDConnectProvider",
                "iam:ListOpenIDConnectProviders",
                "iam:DeleteRolePolicy",
                "iam:UpdateRole",
                "iam:DeleteOpenIDConnectProvider",
                "iam:GetRolePolicy"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Route53",
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZonesByVPC",
                "route53:CreateHostedZone",
                "route53:ListHostedZones",
                "route53:ChangeResourceRecordSets",
                "route53:ListResourceRecordSets",
                "route53:DeleteHostedZone",
                "route53:AssociateVPCWithHostedZone",
                "route53:ListHostedZonesByName"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3",
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets",
                "s3:ListBucket",
                "s3:DeleteObject",
                "s3:DeleteBucket"
            ],
            "Resource": "*"
        }
    ]
}
POLICYEOF

aws iam put-role-policy \
    --role-name "$IAM_ROLE_NAME" \
    --policy-name hcp-cli-policy \
    --policy-document file://"$PROJECT_DIR/tmp/hcp_policy.json"

# Step 11: Get STS session token
echo "🎫 Getting STS session token..."

# Get pull secret file path to determine where to save sts-creds.json (same directory)
PULL_SECRET_FILE=$(yq eval '.hub_cluster.pull_secret_file' "$PROJECT_DIR/config.yaml" 2>/dev/null || echo "")
if [ -n "$PULL_SECRET_FILE" ] && [ -f "$PROJECT_DIR/$PULL_SECRET_FILE" ]; then
    # Use the same directory as pull secret
    PULL_SECRET_DIR=$(dirname "$PROJECT_DIR/$PULL_SECRET_FILE")
    STS_CREDS_FILE="$PULL_SECRET_DIR/sts-creds.json"
    echo "   Saving STS credentials to same directory as pull secret: $STS_CREDS_FILE"
else
    # Fallback to tmp directory if pull secret path not found
    STS_CREDS_FILE="$PROJECT_DIR/tmp/sts-creds.json"
    echo "   Warning: Pull secret file not found in config, using default location: $STS_CREDS_FILE"
fi

# Create directory if it doesn't exist
mkdir -p "$(dirname "$STS_CREDS_FILE")"

aws sts get-session-token --output json > "$STS_CREDS_FILE"

echo "✅ AWS prerequisites setup completed!"
echo "📝 Role ARN saved: $ROLE_ARN"
echo "📝 STS credentials saved to: $STS_CREDS_FILE"

