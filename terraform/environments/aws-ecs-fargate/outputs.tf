output "alb_dns_name" {
  description = "Public Application Load Balancer endpoint URL"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_arn" {
  description = "Amazon Resource Name of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_discovery_namespace" {
  description = "Private Service Connect Cloud Map namespace"
  value       = aws_service_discovery_http_namespace.internal.name
}
