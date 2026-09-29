output "deployment_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "github_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "ecr_repository" {
  value = data.aws_ecr_repository.app.name
}

output "ecs_cluster" {
  value = aws_ecs_cluster.app.name
}

output "ecs_service" {
  value = aws_ecs_service.app.name
}

output "ecs_task_family" {
  value = aws_ecs_task_definition.app.family
}

output "ecs_container_name" {
  value = "${local.name}-app"
}

