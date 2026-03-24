variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (staging|production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'"
  }
}

variable "nvidia_api_key" {
  description = "NVIDIA API key for Nemotron inference. Get from https://build.nvidia.com"
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (ECS tasks)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "ecr_repository_name" {
  description = "Name for the ECR repository"
  type        = string
  default     = "nemoclaw"
}

variable "container_port" {
  description = "Port the NemoClaw container listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "ALB health check path"
  type        = string
  default     = "/health"
}

variable "task_cpu" {
  description = "ECS task CPU units (1 vCPU = 1024)"
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "task_cpu must be a valid Fargate CPU value: 256, 512, 1024, 2048, 4096"
  }
}

variable "task_memory" {
  description = "ECS task memory in MiB (NemoClaw recommends 8GB+)"
  type        = number
  default     = 8192
}

variable "desired_count" {
  description = "Desired number of ECS task instances"
  type        = number
  default     = 1
}
