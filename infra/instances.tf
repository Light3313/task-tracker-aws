# AMIs pinned (not floating SSM "latest") so instances aren't replaced on every new AL2023 —
# a NAT replacement resets its ENI source_dest_check and breaks forwarding. Bump deliberately.
locals {
  ami_al2023_arm    = "ami-02e447f4c654c7179" # AL2023 arm64  (NAT)
  ami_al2023_x86_64 = "ami-0fd6240f599091088" # AL2023 x86_64 (app)
}

# NAT configuration
resource "aws_network_interface" "nat" {
  subnet_id         = aws_subnet.public_1a.id
  security_groups   = [aws_security_group.sg_nat.id]
  source_dest_check = false

  tags = {
    Name = "tt-nat"
  }
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "tt-nat-eip"
  }
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

  tags = {
    Name = "tt-nat"
  }
}

# App configuration
resource "aws_instance" "app" {
  ami                    = local.ami_al2023_x86_64
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.sg_ec2.id]
  subnet_id              = aws_subnet.private_1a.id
  iam_instance_profile   = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              # AL2023 ships neither docker nor the aws cli — both come from the default repos
              dnf install -y --allowerasing docker awscli-2
              systemctl enable --now docker

              REGION=us-east-1

              # No secrets are handled here. The app fetches them at runtime with the instance
              # role: the DB IAM token via @aws-sdk/rds-signer, and SESSION_SECRET from SSM.
              # Keeping them out of user_data keeps them out of the instance system log.

              # ECR login (token valid 12h); derive the registry host from the image URI itself
              APP_IMAGE="${var.app_image}"
              REGISTRY=$(echo "$APP_IMAGE" | cut -d/ -f1)
              aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

              docker pull "$APP_IMAGE"

              # Run with container hardening: read-only rootfs + tmpfs, drop all caps,
              # no-new-privileges, cgroup limits (mem/cpu/pids). Non-root (node) is already in the image.
              docker run -d \
                --name tt-app \
                --restart unless-stopped \
                -p 3000:3000 \
                --read-only \
                --tmpfs /tmp \
                --cap-drop ALL \
                --security-opt no-new-privileges \
                --memory 256m \
                --cpus 0.5 \
                --pids-limit 100 \
                --health-cmd 'wget -qO- http://127.0.0.1:3000/api/healthz || exit 1' \
                --health-interval 10s \
                -e PORT=3000 \
                -e AWS_REGION="$REGION" \
                -e PGHOST="${aws_db_instance.main.address}" \
                -e PGPORT=5432 \
                -e PGUSER=taskuser \
                -e PGDATABASE=tasktracker \
                -e PGSSLMODE=require \
                "$APP_IMAGE"
              EOF

  tags = {
    Name = "tt-app"
  }
}


# IAM
data "aws_iam_policy_document" "ec2_task_tracker_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "app" {
  name = "tt-app-profile"
  role = aws_iam_role.ec2_task_tracker.name
}

resource "aws_iam_role" "ec2_task_tracker" {
  name               = "tt-ec2-task-tracker"
  assume_role_policy = data.aws_iam_policy_document.ec2_task_tracker_assume_role.json
}

resource "aws_iam_role_policy_attachment" "tt_ssm" {
  role       = aws_iam_role.ec2_task_tracker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

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

data "aws_iam_policy_document" "ecr_pull_task_tracker" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["arn:aws:ecr:us-east-1:486949319589:repository/task-tracker"]
  }
}

resource "aws_iam_role_policy" "ssm_read_task_tracker" {
  name   = "ssm-read-task-tracker"
  role   = aws_iam_role.ec2_task_tracker.id
  policy = data.aws_iam_policy_document.ssm_read_task_tracker.json
}

resource "aws_iam_role_policy" "ecr_pull_task_tracker" {
  name   = "ecr-pull-task-tracker"
  role   = aws_iam_role.ec2_task_tracker.id
  policy = data.aws_iam_policy_document.ecr_pull_task_tracker.json
}

data "aws_iam_policy_document" "rds_connect_task_tracker" {
  statement {
    sid       = "RdsIamConnect"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:us-east-1:486949319589:dbuser:${aws_db_instance.main.resource_id}/taskuser"]
  }
}

resource "aws_iam_role_policy" "rds_connect_task_tracker" {
  name   = "rds-connect-task-tracker"
  role   = aws_iam_role.ec2_task_tracker.id
  policy = data.aws_iam_policy_document.rds_connect_task_tracker.json
}

# ALB
#trivy:ignore:AVD-AWS-0053 Public-facing application ALB; internet exposure is intentional
resource "aws_lb" "app" {
  name               = "tt-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_alb.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = {
    Name = "tt-app-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "tt-app-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/api/healthz"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "tt-app-tg"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 3000
}

#trivy:ignore:AVD-AWS-0054 HTTP-only listener; TLS/HTTPS termination via ACM to be added
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

output "app_url" {
  value       = aws_lb.app.dns_name
  description = "The URL of the task tracker app"
}
