resource "aws_ecs_cluster" "tt_ecs" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.tags, { Name = "${local.name}-cluster" })
}

# Group created here, not by the agent — AmazonECSTaskExecutionRolePolicy grants
# CreateLogStream/PutLogEvents but not CreateLogGroup
#trivy:ignore:AVD-AWS-0017 default CWL encryption is sufficient
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.name}"
  retention_in_days = 7

  tags = merge(local.tags, { Name = "/ecs/${local.name}" })
}

# IAM assume role policy — both roles are assumed by the same service
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM execution role — infrastructure side, used before the container exists
resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy_attachment" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy" "ecs_ssm_read" {
  name   = "${local.name}-ecs-ssm-read"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ssm_read_task_tracker.json
}

resource "aws_iam_role_policy" "ecs_rds_connect" {
  name   = "${local.name}-ecs-rds-connect"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.rds_connect_task_tracker.json
}

data "aws_region" "current" {}

resource "aws_ecs_task_definition" "tt_task" {
  family = "${local.name}-app"

  cpu    = 256
  memory = 512

  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    { name      = "task-tracker"
      image     = var.app_image
      essential = true

      portMappings = [
        { containerPort = 3000, protocol = "tcp" }
      ]

      environment = [
        { name = "HOSTNAME", value = "0.0.0.0" },
        { name = "PORT", value = "3000" },
        { name = "AWS_REGION", value = data.aws_region.current.region },
        { name = "PGHOST", value = aws_db_instance.main.address },
        { name = "PGPORT", value = "5432" },
        { name = "PGUSER", value = "taskuser" },
        { name = "PGDATABASE", value = "tasktracker" },
        { name = "PGSSLMODE", value = "require" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/api/healthz || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

    }
  ])

  tags = merge(local.tags, { Name = "${local.name}-app" })
}

resource "aws_lb_target_group" "app_ecs" {
  name        = "${local.name}-app-ecs-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = "/api/healthz"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = merge(local.tags, { Name = "${local.name}-app-ecs-tg" })
}

resource "aws_lb_listener_rule" "ecs_canary" {
  listener_arn = aws_lb_listener.app_https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_ecs.arn
  }

  condition {
    http_header {
      http_header_name = "X-Canary"
      values           = ["ecs"]
    }
  }

  tags = merge(local.tags, { Name = "${local.name}-ecs-canary" })
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-app"
  cluster         = aws_ecs_cluster.tt_ecs.id
  task_definition = aws_ecs_task_definition.tt_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.this["private_1a"].id,
      aws_subnet.this["private_1b"].id,
    ]
    security_groups  = [aws_security_group.sg_ec2.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_ecs.arn
    container_name   = "task-tracker"
    container_port   = 3000
  }

  health_check_grace_period_seconds = 60

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  wait_for_steady_state = true

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.ecs_canary]
}

resource "aws_appautoscaling_target" "ecs_app" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.tt_ecs.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_app" {
  name               = "${local.name}-ecs-app"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_app.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = 70
  }
}
