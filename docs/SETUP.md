# Setup Guide

Step-by-step: Deploy NemoClaw to AWS from scratch.

---

## 1. Prerequisites

- [ ] AWS account with admin or IAM power-user access
- [ ] [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 installed
- [ ] [AWS CLI v2](https://aws.amazon.com/cli/) installed and configured (`aws configure`)
- [ ] [Docker](https://docs.docker.com/get-docker/) installed
- [ ] GitHub repository (fork or clone this repo)
- [ ] NVIDIA API key from [build.nvidia.com](https://build.nvidia.com)

---

## 2. Get NVIDIA API Key

1. Go to [build.nvidia.com](https://build.nvidia.com)
2. Sign in / create account
3. Go to **API Keys** → **Generate Personal Key**
4. Copy the key (starts with `nvapi-`)
5. Store it safely — you'll need it for Secrets Manager

---

## 3. AWS Setup

### 3a. Create Terraform State Backend

```bash
# Create S3 bucket for state (replace with unique bucket name)
aws s3 mb s3://YOUR-nemoclaw-tfstate --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket YOUR-nemoclaw-tfstate \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name nemoclaw-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 3b. Update backend.tf

Edit `terraform/backend.tf`:
```hcl
backend "s3" {
  bucket         = "YOUR-nemoclaw-tfstate"   # ← your bucket
  key            = "nemoclaw/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "nemoclaw-tfstate-lock"
}
```

### 3c. Create IAM Role for GitHub Actions (OIDC)

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create OIDC provider for GitHub
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role (replace YOUR_GITHUB_ORG/YOUR_REPO)
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
      },
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF

# Replace ACCOUNT_ID
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" trust-policy.json

# Create role
aws iam create-role \
  --role-name nemoclaw-github-actions \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions (adjust as needed)
aws iam attach-role-policy \
  --role-name nemoclaw-github-actions \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

aws iam attach-role-policy \
  --role-name nemoclaw-github-actions \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess

aws iam attach-role-policy \
  --role-name nemoclaw-github-actions \
  --policy-arn arn:aws:iam::aws:policy/AmazonElasticLoadBalancingFullAccess

# Get role ARN (you'll need this for GitHub secret)
aws iam get-role --role-name nemoclaw-github-actions --query Role.Arn --output text
```

---

## 4. GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret Name | Value | Where to get it |
|-------------|-------|-----------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/nemoclaw-github-actions` | Step 3c output |
| `NVIDIA_API_KEY` | `nvapi-xxxx...` | build.nvidia.com |
| `AWS_REGION` | `us-east-1` | Your chosen region |
| `TF_BACKEND_BUCKET` | `YOUR-nemoclaw-tfstate` | Step 3a |
| `TF_BACKEND_REGION` | `us-east-1` | Your chosen region |
| `SLACK_WEBHOOK_URL` | `https://hooks.slack.com/...` | Slack app (optional) |

---

## 5. GitHub Environments

For production protection (manual approval):

1. Go to **Settings** → **Environments** → **New environment**
2. Name it `production`
3. Under **Deployment protection rules** → enable **Required reviewers**
4. Add yourself (and team) as required reviewers
5. Repeat for `staging` (no reviewers needed)

---

## 6. Deploy Infrastructure

```bash
cd terraform

# Initialize
terraform init \
  -backend-config="bucket=YOUR-nemoclaw-tfstate" \
  -backend-config="region=us-east-1"

# Plan (staging)
terraform plan \
  -var="nvidia_api_key=nvapi-YOUR-KEY" \
  -var="environment=staging"

# Apply
terraform apply \
  -var="nvidia_api_key=nvapi-YOUR-KEY" \
  -var="environment=staging"

# Note the outputs
terraform output
```

---

## 7. Configure GitHub Actions with Terraform Outputs

After `terraform apply`, copy these outputs to GitHub Secrets:

```bash
terraform output ecr_repository_url   # → update ECR_REPOSITORY in workflows
terraform output ecs_cluster_name     # → ECS_CLUSTER secret
terraform output ecs_service_name     # → ECS_SERVICE secret
```

---

## 8. First Deployment

Push to `main` to trigger the full CI/CD pipeline:

```bash
git add .
git commit -m "feat: initial nemoclaw deployment"
git push origin main
```

Watch it run:
- **Actions tab** → CI runs first
- On completion → CD Staging triggers
- Check ALB URL: `terraform output alb_url`

---

## 9. Deploy to Production

1. Go to **Actions** → **CD - Production**
2. Click **Run workflow**
3. Enter the image tag from staging (e.g. `abc1234`)
4. Type `deploy` in the confirmation field
5. Click **Run workflow**
6. Approve when GitHub Environment prompts you

---

## 10. Local Testing

```bash
cp .env.example .env
# Edit .env with your NVIDIA_API_KEY

docker-compose up --build
# → http://localhost:3000
```

---

## Troubleshooting

See [README.md troubleshooting section](../README.md#troubleshooting) and [NemoClaw Docs](https://docs.nvidia.com/nemoclaw/latest/reference/troubleshooting.html).
