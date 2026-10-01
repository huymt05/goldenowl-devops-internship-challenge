terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "goldenowl-tfstate-304152263685-ap-southeast-1"
    key          = "goldenowl/app.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ecr_repository" "app" {
  name = "goldenowl-app"
}

locals {
  name          = "goldenowl"
  app_domain    = "app.huymt05-goldenowlchallenge.io.vn"
  initial_image = "${data.aws_ecr_repository.app.repository_url}:bootstrap"
}

# DNS is managed at VinaHost. Request the certificate first, then publish the
# ACM validation CNAME from the acm_validation_record output in VinaHost.
resource "aws_acm_certificate" "app" {
  domain_name       = local.app_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# VinaHost hosts the DNS validation CNAME; see acm_validation_record output.
resource "aws_acm_certificate_validation" "app" {
  certificate_arn = aws_acm_certificate.app.arn
  validation_record_fqdns = [
    for option in aws_acm_certificate.app.domain_validation_options : option.resource_record_name
  ]
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name   = "${local.name}-alb-sg"
  vpc_id = aws_vpc.main.id

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

resource "aws_security_group" "ecs" {
  name   = "${local.name}-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
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

resource "aws_lb" "app" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "blue" {
  name        = "${local.name}-blue"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${local.name}-green"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Keep this resource address so the ECS canary production listener rule keeps
# pointing at the same listener ARN when HTTP is upgraded to HTTPS.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      host        = local.app_domain
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  # Port 80 is released by the existing production listener first.
  depends_on = [aws_lb_listener.http]
}

resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = 1
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    # ECS manages the target group weights during canary deployments.
    ignore_changes = [action]
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}-app"
  retention_in_days = 7
}

# ECS alternates the blue and green target groups between canary deployments.
# Idle groups may emit no request metrics, so missing data must not trigger rollback.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = {
    blue  = aws_lb_target_group.blue.arn_suffix
    green = aws_lb_target_group.green.arn_suffix
  }

  alarm_name          = "${local.name}-${each.key}-target-5xx"
  alarm_description   = "Application 5xx responses during ECS canary deployment"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 3
  period              = 60
  statistic           = "Sum"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = each.value
  }
}

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_infrastructure" {
  name = "${local.name}-ecs-infrastructure"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  role       = aws_iam_role.ecs_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

resource "aws_ecs_cluster" "app" {
  name = "${local.name}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "${local.name}-app"
    image     = local.initial_image
    essential = true

    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = "ap-southeast-1"
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                              = "${local.name}-service"
  cluster                           = aws_ecs_cluster.app.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = 2
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60
  wait_for_steady_state             = false

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy             = "CANARY"
    bake_time_in_minutes = 5

    canary_configuration {
      canary_percent              = 10
      canary_bake_time_in_minutes = 5
    }
  }

  alarms {
    alarm_names = [for alarm in aws_cloudwatch_metric_alarm.target_5xx : alarm.alarm_name]
    enable      = true
    rollback    = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "${local.name}-app"
    container_port   = 3000

    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.green.arn
      production_listener_rule   = aws_lb_listener_rule.production.arn
      role_arn                   = aws_iam_role.ecs_infrastructure.arn
    }
  }

  lifecycle {
    # GitHub Actions manages task revisions; autoscaling manages desired_count.
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [
    aws_lb_listener_rule.production,
    aws_iam_role_policy_attachment.ecs_execution,
    aws_iam_role_policy_attachment.ecs_infrastructure
  ]
}

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.app.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

