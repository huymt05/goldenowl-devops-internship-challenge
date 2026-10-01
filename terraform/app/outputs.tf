output "deployment_url" {
  value = "https://${local.app_domain}"
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "acm_certificate_arn" {
  value = aws_acm_certificate.app.arn
}

output "acm_validation_record" {
  description = "Add this CNAME in VinaHost DNS Manager to validate the HTTPS certificate."
  value = one([
    for option in aws_acm_certificate.app.domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ])
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

