# NAT configuration
resource "aws_network_interface" "nat" {
  subnet_id         = aws_subnet.this["public_1a"].id
  security_groups   = [aws_security_group.sg_nat.id]
  source_dest_check = false

  tags = merge(local.tags, { Name = "${local.name}-nat" })
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.tags, { Name = "${local.name}-nat-eip" })
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}

resource "aws_instance" "nat" {
  ami           = local.ami_al2023_arm
  instance_type = "t4g.micro"
  metadata_options { http_tokens = "required" }

  primary_network_interface {
    network_interface_id = aws_network_interface.nat.id
  }

  root_block_device {
    encrypted = true
  }

  lifecycle {
    # source_dest_check can't be set here (conflicts with primary_network_interface), yet the
    # schema defaults it to true and would reset the ENI to true on every apply, killing NAT
    # forwarding. Ignore it and let aws_network_interface.nat own source_dest_check = false.
    ignore_changes = [source_dest_check]
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              dnf install -y iptables-services

              # Enable IP forwarding and persist across reboot (without it MASQUERADE forwards nothing)
              echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
              sysctl --system

              # Primary interface on AL2023 is ens5/enX0, not eth0 -> derive it from the default route
              PRIMARY_IF=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)

              # NAT: masquerade outbound traffic from the private subnets
              iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE

              # Persist the rules so they survive a reboot
              systemctl enable iptables
              service iptables save
              EOF

  tags = merge(local.tags, { Name = "${local.name}-nat" })
}

# IAM — policy documents consumed by the ECS task role (see ecs.tf)
data "aws_iam_policy_document" "ssm_read_task_tracker" {
  statement {
    sid    = "ReadTaskTrackerParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:us-east-1:486949319589:parameter/task-tracker/*",
    ]
  }
  statement {
    sid       = "DecryptViaSSMOnly"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.us-east-1.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "rds_connect_task_tracker" {
  statement {
    sid       = "RdsIamConnect"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:us-east-1:486949319589:dbuser:${aws_db_instance.main.resource_id}/taskuser"]
  }
}

# ALB
#trivy:ignore:AVD-AWS-0053 Public-facing application ALB; internet exposure is intentional
resource "aws_lb" "app" {
  name               = "${local.name}-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_alb.id]
  subnets            = [aws_subnet.this["public_1a"].id, aws_subnet.this["public_1b"].id]

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = merge(local.tags, { Name = "${local.name}-app-alb" })
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = 443
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "app_https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_ecs.arn
  }
}
