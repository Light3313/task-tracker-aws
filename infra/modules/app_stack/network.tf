resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

# AWS Subnets
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, each.value.netnum)
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.name}-${each.key}" })
}

# Route Associations
resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = each.value.tier == "public" ? aws_route_table.public_rt.id : aws_route_table.private_rt.id
}

# IGW
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name}-igw" })
}

# Route tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name}-private-rt" })
}

# Routes
resource "aws_route" "public_rt_route" {
  route_table_id = aws_route_table.public_rt.id

  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route" "private_rt_route" {
  route_table_id = aws_route_table.private_rt.id

  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.nat.id
}

# Flow Logs for main VPC
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

#trivy:ignore:AVD-AWS-0017 default CWL encryption is sufficient
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/vpc/task-tracker/${var.env_name}/vpc-flowlogs"
  retention_in_days = 3
}

data "aws_iam_policy_document" "flow_logs_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name               = "${local.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_trust.json
}

data "aws_iam_policy_document" "flow_logs_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "access_cloudwatch_logging" {
  name   = "AccessCloudWatchLogging"
  role   = aws_iam_role.vpc_flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_permissions.json
}
