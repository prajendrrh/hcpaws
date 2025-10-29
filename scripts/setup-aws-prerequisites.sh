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

# Source AWS credentials
source "$PROJECT_DIR/aws-credentials.env"
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

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
cat > "$PROJECT_DIR/tmp/credentials" <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF

# Step 6: Get kubeconfig
if [ ! -f "$PROJECT_DIR/installer/auth/kubeconfig" ]; then
    echo "Error: kubeconfig not found. Please ensure the hub cluster is installed."
    exit 1
fi

export KUBECONFIG="$PROJECT_DIR/installer/auth/kubeconfig"

# Step 7: Create secret for hypershift operator
echo "🔐 Creating hypershift operator OIDC provider secret..."
oc create secret generic hypershift-operator-oidc-provider-s3-credentials \
    --from-file=credentials="$PROJECT_DIR/tmp/credentials" \
    --from-literal=bucket="$BUCKET_NAME" \
    --from-literal=region="$HOSTED_REGION" \
    -n local-cluster \
    --dry-run=client -o yaml | oc apply -f - || echo "  Secret may already exist"

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

# Step 10: Create系统中的 IAM role policy
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
aws sts get-session-token --output json > "$PROJECT_DIR/tmp/sts-creds.json"

echo "✅ AWS prerequisites setup completed!"
echo "📝 Role ARN saved: $ROLE_ARN"
echo "📝 STS credentials saved to: $PROJECT_DIR/tmp/sts-creds.json"

