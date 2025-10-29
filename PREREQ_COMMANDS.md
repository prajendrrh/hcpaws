# AWS Prerequisites and Hosted Cluster Creation Commands

**Replace these variables with your actual values:**
- `<BUCKET_NAME>` - Your S3 bucket name (e.g., my-hcp-bucket)
- `<REGION>` - AWS region (e.g., eu-west-2)
- `<USER_ARN>` - Your AWS user ARN
- `<IAM_ROLE_NAME>` - IAM role name (e.g., hcp-guide)
- `<CLUSTER_NAME>` - Hosted cluster name
- `<INFRA_ID>` - Infrastructure ID (usually same as cluster name)
- `<BASE_DOMAIN>` - Base domain
- `<ZONES>` - Comma-separated zones (e.g., eu-west-2a,eu-west-2b,eu-west-2c)
- `<NAMESPACE>` - Namespace in ACM
- `<NODE_POOL_REPLICAS>` - Number of node pool replicas
- `<RELEASE_IMAGE>` - OCP release image
- `<PULL_SECRET_FILE>` - Path to pull-secret file

---

## Step 1: Get AWS User ARN

```bash
aws sts get-caller-identity --query "Arn" --output text
```

**Save the output as `<USER_ARN>`**

---

## Step 2: Create S3 Bucket

```bash
aws s3api create-bucket --bucket <BUCKET_NAME> --create-bucket-configuration LocationConstraint=<REGION> --region <REGION>
```

---

## Step 3: Delete Public Access Block

```bash
aws s3api delete-public-access-block --bucket <BUCKET_NAME>
```

---

## Step 4: Create Bucket Policy

**Using envsubst (recommended):**
```bash
export BUCKET_NAME=<BUCKET_NAME>
echo '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::'"${BUCKET_NAME}"'/*" 
        }
    ]
}' | envsubst > policy.json
```

**Or manually:**
```bash
cat > policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::<BUCKET_NAME>/*" 
        }
    ]
}
EOF
```

---

## Step 5: Apply Bucket Policy

```bash
aws s3api put-bucket-policy --bucket <BUCKET_NAME> --policy file://policy.json
```

---

## Step 6: Create Credentials File

```bash
cat > credentials <<EOF
[default]
aws_access_key_id=<AWS_ACCESS_KEY_ID>
aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>
EOF
```

---

## Step 7: Create Secret in Kubernetes

**Set your kubeconfig first:**
```bash
export KUBECONFIG=/path/to/auth/kubeconfig
```

**Delete existing secret (if any):**
```bash
oc delete secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster
```

**Create the secret:**
```bash
oc create secret generic hypershift-operator-oidc-provider-s3-credentials \
    --from-file=credentials=credentials \
    --from-literal=bucket=<BUCKET_NAME> \
    --from-literal=region=<REGION> \
    -n local-cluster
```

**Verify the secret was created:**
```bash
oc get secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster
```

---

## Step 8: Create IAM Role Trust Policy

**Using envsubst:**
```bash
```bash
export USER_ARN=<USER_ARN>
echo '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "'"${USER_ARN}"'"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}' | envsubst > iam_role.json
```

**Or manually:**
```bash
cat > iam_role.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "<USER_ARN>"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
```

---

## Step 9: Create IAM Role

```bash
aws iam create-role \
  --role-name <IAM_ROLE_NAME> \
  --assume-role-policy-document file://iam_role.json \
  --query "Role.Arn"
```

**Save the output as `<ROLE_ARN>`**

If role already exists, get ARN:
```bash
aws iam get-role --role-name <IAM_ROLE_NAME> --query "Role.Arn" --output text
```

---

## Step 10: Create HCP Policy

**Create hcp_policy.json file:**

```bash
cat > hcp_policy.json <<'EOF'
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
EOF
```

---

## Step 11: Attach Policy to IAM Role

```bash
aws iam put-role-policy \
  --role-name <IAM_ROLE_NAME> \
  --policy-name hcp-cli-policy \
  --policy-document file://hcp_policy.json
```

---

## Step 12: Get STS Session Token

```bash
aws sts get-session-token --output json > sts-creds.json
```

---

## Step 13: Create Hosted Cluster

```bash
hcp create cluster aws \
    --name <CLUSTER_NAME> \
    --infra-id <INFRA_ID> \
    --base-domain <BASE_DOMAIN> \
    --sts-creds sts-creds.json \
    --pull-secret <PULL_SECRET_FILE> \
    --region <REGION> \
    --zones <ZONES> \
    --generate-ssh \
    --node-pool-replicas <NODE_POOL_REPLICAS> \
    --namespace <NAMESPACE> \
    --role-arn <ROLE_ARN> \
    --release-image <RELEASE_IMAGE>
```

---

## Verification Commands

**Check secret in cluster:**
```bash
oc get secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster -o yaml
oc describe secret hypershift-operator-oidc-provider-s3-credentials -n local-cluster
```

**Check S3 bucket:**
```bash
aws s3 ls s3://<BUCKET_NAME>
aws s3api get-bucket-policy --bucket <BUCKET_NAME>
```

**Check IAM role:**
```bash
aws iam get-role --role-name <IAM_ROLE_NAME>
aws iam get-role-policy --role-name <IAM_ROLE_NAME> --policy-name hcp-cli-policy
```
