# NemoClaw AWS Architecture

## What is NemoClaw?

[NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) (alpha, March 2026) is an open-source reference stack that runs [OpenClaw](https://openclaw.ai) AI agents securely inside **NVIDIA OpenShell** sandboxes — with Nemotron models for inference.

It solves a key problem: running autonomous AI agents safely by enforcing network egress policies, filesystem isolation, and routing all inference calls through a controlled gateway.

---

## NemoClaw Component Stack

```
┌──────────────────────────────────────────────────────┐
│  nemoclaw CLI (TypeScript npm package)               │
│  → onboard, connect, start, stop, status, logs       │
└────────────────────┬─────────────────────────────────┘
                     │ orchestrates
┌────────────────────▼─────────────────────────────────┐
│  Blueprint (versioned Python artifact)               │
│  → resolves digest → plans resources → applies       │
└────────────────────┬─────────────────────────────────┘
                     │ creates
┌────────────────────▼─────────────────────────────────┐
│  OpenShell Sandbox                                   │
│  ┌────────────────────────────────────────────────┐  │
│  │  OpenClaw Agent                                │  │
│  │  (identity, memory, skills, heartbeat)         │  │
│  │                                                │  │
│  │  ← filesystem: /sandbox + /tmp only            │  │
│  │  ← network: only whitelisted egress            │  │
│  │  ← syscalls: Landlock + seccomp                │  │
│  └─────────────────────┬──────────────────────────┘  │
│                        │ inference calls              │
│  ┌─────────────────────▼──────────────────────────┐  │
│  │  OpenShell Gateway                             │  │
│  │  → intercepts → routes to NVIDIA Endpoint      │  │
│  └─────────────────────┬──────────────────────────┘  │
└────────────────────────┼─────────────────────────────┘
                         │ HTTPS
┌────────────────────────▼─────────────────────────────┐
│  NVIDIA Endpoint API (build.nvidia.com)              │
│  Model: nvidia/nemotron-3-super-120b-a12b            │
└──────────────────────────────────────────────────────┘
```

---

## AWS Hosting Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  AWS Region (us-east-1)                                     │
│                                                             │
│  ┌─── VPC (10.0.0.0/16) ───────────────────────────────┐   │
│  │                                                      │   │
│  │  ┌── Public Subnets ──────────────────────────────┐  │   │
│  │  │  AZ-a: 10.0.1.0/24   AZ-b: 10.0.2.0/24       │  │   │
│  │  │                                                │  │   │
│  │  │  ┌──────────────────────────────────────────┐ │  │   │
│  │  │  │  Application Load Balancer               │ │  │   │
│  │  │  │  Port 80 → Target Group → ECS tasks      │ │  │   │
│  │  │  └──────────────────────────────────────────┘ │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │                                                      │   │
│  │  ┌── Private Subnets ─────────────────────────────┐  │   │
│  │  │  AZ-a: 10.0.10.0/24  AZ-b: 10.0.11.0/24      │  │   │
│  │  │                                                │  │   │
│  │  │  ┌──────────────────────────────────────────┐ │  │   │
│  │  │  │  ECS Fargate Service                     │ │  │   │
│  │  │  │  NemoClaw Container (Port 3000)           │ │  │   │
│  │  │  │  CPU: 1024 | Memory: 8192 MiB             │ │  │   │
│  │  │  └──────────────────────────────────────────┘ │  │   │
│  │  │        │                  │                   │  │   │
│  │  │        ▼ NAT GW           ▼ VPC Endpoints     │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ECR ──────── stores Docker images                          │
│  Secrets Manager ── NVIDIA_API_KEY                         │
│  CloudWatch Logs ── /ecs/nemoclaw-<env>                     │
│  IAM ────────────── least-privilege task roles             │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼ HTTPS
               NVIDIA Endpoint API
               (nemotron-3-super-120b-a12b)
```

---

## CI/CD Pipeline

```
Developer Push
      │
      ▼
GitHub Actions: CI
  ├── ShellCheck (scripts)
  ├── YAML Lint (workflows)
  ├── Hadolint (Dockerfile)
  ├── Terraform fmt + validate
  └── Trivy security scan (FS + image)
      │
      ▼ (merge to main)
GitHub Actions: CD Staging
  ├── docker build + tag with git SHA
  ├── push to ECR
  ├── ECS update-service (staging)
  ├── wait for stability
  └── smoke test (/health endpoint)
      │
      ▼ (manual dispatch + approval)
GitHub Actions: CD Production
  ├── re-tag image as production-<sha>
  ├── ECS update-service (production)
  ├── wait for stability (15 min)
  ├── smoke test
  └── git tag deployment
```

---

## Security Model

### Network (OpenShell)
- All outbound traffic blocked by default
- Only explicitly whitelisted endpoints allowed
- Unrecognized requests surfaced for operator approval
- Policy hot-reloadable at runtime

### Filesystem (OpenShell)
- Reads/writes restricted to `/sandbox` and `/tmp`
- Locked at sandbox creation

### Process (OpenShell)
- Landlock + seccomp enforced
- Privilege escalation blocked

### AWS (IAM least privilege)
- ECS task execution role: only ECR pull + Secrets Manager read + CloudWatch write
- ECS task role: only CloudWatch log write
- No wildcard permissions

### Inference Routing
- Agent inference calls never leave sandbox directly
- OpenShell gateway intercepts and routes to NVIDIA Endpoint
- NVIDIA_API_KEY stored in AWS Secrets Manager, injected at runtime

---

## Environments

| | Staging | Production |
|---|---|---|
| Capacity | FARGATE_SPOT | FARGATE |
| NAT Gateways | 1 (single) | 2 (per-AZ) |
| Desired count | 1 | configurable |
| Deploy trigger | Auto (push to main) | Manual dispatch |
| Approval | None | GitHub Environment protection |

---

## References

- [NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw)
- [NemoClaw Docs](https://docs.nvidia.com/nemoclaw/latest/)
- [NemoClaw Architecture](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html)
- [OpenShell](https://github.com/NVIDIA/OpenShell)
- [OpenShell Policy Schema](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html)
