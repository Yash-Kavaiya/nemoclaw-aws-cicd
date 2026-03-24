# NemoClaw AWS CI/CD Pipeline

> Deploy [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) to AWS using GitHub Actions + Terraform.

NemoClaw is an open-source reference stack (alpha, March 2026) that runs [OpenClaw](https://openclaw.ai) always-on agents securely inside [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) sandboxes, powered by Nemotron models.

---

## Architecture

```
GitHub ──push──► CI (lint + tf-plan + trivy)
                       │
              merge to main
                       │
                       ▼
         CD Staging ──► ECR ──► ECS Fargate (staging)
                                      │
                               smoke tests pass
                                      │
                      manual approve (GitHub Environments)
                                      │
                                      ▼
         CD Production ──► Blue/Green ECS (production)
                                      │
                              ALB traffic shift
```

```
┌─────────────────────────────────────────────────────────┐
│  AWS Region                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  VPC (10.0.0.0/16)                               │  │
│  │  ┌──────────┐  ┌──────────┐                      │  │
│  │  │ Public   │  │ Private  │                      │  │
│  │  │ Subnet   │  │ Subnet   │                      │  │
│  │  │  (ALB)   │  │  (ECS)   │                      │  │
│  │  └────┬─────┘  └────┬─────┘                      │  │
│  │       │              │                            │  │
│  │  ┌────▼─────────────▼─────┐                      │  │
│  │  │  Application Load      │                      │  │
│  │  │  Balancer (:80/:443)   │                      │  │
│  │  └────────────┬───────────┘                      │  │
│  │               │                                  │  │
│  │  ┌────────────▼───────────┐                      │  │
│  │  │  ECS Fargate Service   │                      │  │
│  │  │  NemoClaw Container    │                      │  │
│  │  │  (nemotron inference)  │                      │  │
│  │  └────────────────────────┘                      │  │
│  │                                                  │  │
│  │  ECR ─── Secrets Manager ─── CloudWatch Logs    │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- AWS account with IAM permissions for ECS, ECR, ALB, VPC, Secrets Manager
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI v2](https://aws.amazon.com/cli/) configured
- [Docker](https://docs.docker.com/get-docker/)
- [NVIDIA API Key](https://build.nvidia.com) for Nemotron inference
- GitHub repository with Actions enabled

---

## Quick Start

### 1. Fork/Clone

```bash
git clone https://github.com/YOUR_ORG/nemoclaw-aws-cicd
cd nemoclaw-aws-cicd
```

### 2. Configure AWS Backend

Create S3 bucket and DynamoDB table for Terraform state:

```bash
aws s3 mb s3://your-nemoclaw-tfstate --region us-east-1
aws dynamodb create-table \
  --table-name nemoclaw-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Update `terraform/backend.tf` with your bucket name.

### 3. Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC |
| `NVIDIA_API_KEY` | From [build.nvidia.com](https://build.nvidia.com) |
| `SLACK_WEBHOOK_URL` | (Optional) Slack incoming webhook |
| `TF_BACKEND_BUCKET` | S3 bucket name for Terraform state |
| `TF_BACKEND_REGION` | AWS region |

### 4. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan -var="nvidia_api_key=YOUR_KEY"
terraform apply -var="nvidia_api_key=YOUR_KEY"
```

### 5. First Deploy

Push to `main` — CI/CD will trigger automatically:
```bash
git add .
git commit -m "feat: initial nemoclaw deployment"
git push origin main
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `NVIDIA_API_KEY` | ✅ | Nemotron model access key |
| `AWS_REGION` | ✅ | AWS deployment region (e.g. `us-east-1`) |
| `ECR_REPOSITORY` | ✅ | ECR repo name (from terraform output) |
| `ECS_CLUSTER` | ✅ | ECS cluster name |
| `ECS_SERVICE` | ✅ | ECS service name |
| `ECS_TASK_FAMILY` | ✅ | Task definition family name |
| `SLACK_WEBHOOK_URL` | ❌ | Slack notifications |

---

## Workflows

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `ci.yml` | push / PR | Lint, Terraform validate, Trivy scan |
| `cd-staging.yml` | merge to `main` | Build → ECR → ECS staging → smoke test |
| `cd-production.yml` | manual dispatch | Promote staging image to production |
| `rollback.yml` | manual dispatch | Roll back to specific image tag |

---

## Deployment Flow

```
1. Developer pushes code
2. CI runs: lint + terraform validate + trivy security scan
3. On merge to main: Docker build → push to ECR with git SHA tag
4. ECS staging service updated → smoke tests run
5. Manual approval required for production
6. Production blue/green deployment via ECS
7. ALB health checks validate new tasks before traffic shift
```

---

## Rollback

**Via GitHub Actions (recommended):**
1. Go to Actions → Rollback workflow
2. Click "Run workflow"
3. Enter the image tag to roll back to (e.g. `abc1234`)

**Via CLI:**
```bash
./scripts/rollback.sh <image-tag>
```

---

## Local Development

```bash
cp .env.example .env
# Edit .env and add your NVIDIA_API_KEY

docker-compose up
# NemoClaw available at http://localhost:3000
```

---

## Troubleshooting

**ECS tasks failing to start:**
- Check CloudWatch logs: `/ecs/nemoclaw-<env>`
- Verify `NVIDIA_API_KEY` is set in Secrets Manager
- Ensure Fargate task has internet access (NAT Gateway or VPC endpoints)

**Terraform state lock:**
```bash
terraform force-unlock <LOCK_ID>
```

**Image push failing:**
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ECR_URL>
```

**NemoClaw sandbox issues:**
- See [NVIDIA NemoClaw Troubleshooting](https://docs.nvidia.com/nemoclaw/latest/reference/troubleshooting.html)
- Check OpenShell policy: `openshell sandbox list`

---

## References

- [NVIDIA NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw)
- [NemoClaw Docs](https://docs.nvidia.com/nemoclaw/latest/)
- [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell)
- [NVIDIA build.nvidia.com (API Keys)](https://build.nvidia.com)

---

## License

Apache 2.0
