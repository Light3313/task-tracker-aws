resource "aws_ecs_cluster" "tt_ecs" {
  name = "${local.name}-cluster"

  tags = merge(local.tags, { Name = "${local.name}-cluster" })
}

# Group created here, not by the agent — AmazonECSTaskExecutionRolePolicy grants
# CreateLogStream/PutLogEvents but not CreateLogGroup
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

  lifecycle {
    ignore_changes = [desired_count]
  }

  container_definitions = jsonencode([
    { name      = "task-tracker"
      image     = var.app_image
      essential = true

      portMappings = [
        { containerPort = 3000, protocol = "tcp" }
      ]

      environment = [
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
