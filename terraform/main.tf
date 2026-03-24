terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "nemoclaw"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name_prefix = "nemoclaw-${var.environment}"
}

# ─── VPC ────────────────────────────────────────────────────────────────────

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ─── ECR ────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "nemoclaw" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "nemoclaw" {
  repository = aws_ecr_repository.nemoclaw.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "production-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── SECRETS MANAGER ────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "nvidia_api_key" {
  name                    = "${local.name_prefix}/nvidia-api-key"
  description             = "NVIDIA Nemotron API key for NemoClaw"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "nvidia_api_key" {
  secret_id     = aws_secretsmanager_secret.nvidia_api_key.id
  secret_string = var.nvidia_api_key
}

# ─── IAM ────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.name_prefix}-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.nvidia_api_key.arn]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy" "ecs_task_cloudwatch" {
  name = "${local.name_prefix}-task-cloudwatch"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["${aws_cloudwatch_log_group.ecs.arn}:*"]
      }
    ]
  })
}

# ─── CLOUDWATCH ─────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
}

# ─── SECURITY GROUPS ────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP/HTTPS inbound to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Allow inbound from ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── ALB ────────────────────────────────────────────────────────────────────

resource "aws_lb" "nemoclaw" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "nemoclaw" {
  name        = "${local.name_prefix}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    path                = var.health_check_path
    matcher             = "200-299"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.nemoclaw.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nemoclaw.arn
  }
}

# ─── ECS ────────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "nemoclaw" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "nemoclaw" {
  cluster_name = aws_ecs_cluster.nemoclaw.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.environment == "production" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "nemoclaw" {
  family                   = "${local.name_prefix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = templatefile("${path.module}/ecs-task-definition.json.tpl", {
    name              = "nemoclaw"
    image             = "${aws_ecr_repository.nemoclaw.repository_url}:latest"
    container_port    = var.container_port
    cpu               = var.task_cpu
    memory            = var.task_memory
    log_group         = aws_cloudwatch_log_group.ecs.name
    aws_region        = var.aws_region
    nvidia_secret_arn = aws_secretsmanager_secret.nvidia_api_key.arn
    environment       = var.environment
  })
}

resource "aws_ecs_service" "nemoclaw" {
  name            = "${local.name_prefix}-svc"
  cluster         = aws_ecs_cluster.nemoclaw.id
  task_definition = aws_ecs_task_definition.nemoclaw.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = var.environment == "production" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nemoclaw.arn
    container_name   = "nemoclaw"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
