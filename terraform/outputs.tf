output "ecr_repository_url" {
  description = "ECR repository URL for pushing NemoClaw images"
  value       = aws_ecr_repository.nemoclaw.repository_url
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.nemoclaw.dns_name
}

output "alb_url" {
  description = "Full HTTP URL to access NemoClaw"
  value       = "http://${aws_lb.nemoclaw.dns_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name (use in GitHub Actions secrets)"
  value       = aws_ecs_cluster.nemoclaw.name
}

output "ecs_service_name" {
  description = "ECS service name (use in GitHub Actions secrets)"
  value       = aws_ecs_service.nemoclaw.name
}

output "ecs_task_family" {
  description = "ECS task definition family name"
  value       = aws_ecs_task_definition.nemoclaw.family
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for ECS task logs"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "nvidia_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the NVIDIA API key"
  value       = aws_secretsmanager_secret.nvidia_api_key.arn
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}
