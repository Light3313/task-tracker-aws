# SG ALB
resource "aws_security_group" "sg_alb" {
  vpc_id = aws_vpc.main.id

  description = "Allow inbound 80 from all IPv4"

  tags = {
    Name = "sg-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_internet_80" {
  security_group_id = aws_security_group.sg_alb.id

  description = "Inbound HTTP from the internet to the ALB"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_egress_all" {
  security_group_id = aws_security_group.sg_alb.id

  description                  = "Forward to the app instances on port 3000"
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.sg_ec2.id
  from_port                    = 3000
  to_port                      = 3000
}


# SG EC2 
resource "aws_security_group" "sg_ec2" {
  vpc_id = aws_vpc.main.id

  description = "Allow inbound 3000 from sg_alb"

  tags = {
    Name = "sg-ec2"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb_3000" {
  security_group_id            = aws_security_group.sg_ec2.id
  referenced_security_group_id = aws_security_group.sg_alb.id

  description = "Inbound app traffic from the ALB on port 3000"
  ip_protocol = "tcp"
  from_port   = 3000
  to_port     = 3000
}

#trivy:ignore:AVD-AWS-0104 Outbound HTTPS to ECR/SSM/S3 via NAT
resource "aws_vpc_security_group_egress_rule" "ec2_egress_all" {
  security_group_id = aws_security_group.sg_ec2.id

  description = "Outbound HTTPS to ECR/SSM/S3 via NAT"
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_rds_5432" {
  security_group_id            = aws_security_group.sg_ec2.id
  referenced_security_group_id = aws_security_group.sg_rds.id

  description = "Outbound PostgreSQL to the RDS instance"
  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}

# SG RDS 
resource "aws_security_group" "sg_rds" {
  vpc_id = aws_vpc.main.id

  description = "Allow inbound 5432 from sg_ec2"

  tags = {
    Name = "sg-rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2_5432" {
  security_group_id            = aws_security_group.sg_rds.id
  referenced_security_group_id = aws_security_group.sg_ec2.id

  description = "Inbound PostgreSQL from the app instances"
  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}

# SG NAT
resource "aws_security_group" "sg_nat" {
  vpc_id = aws_vpc.main.id

  description = "Allow all inbound from VPC network"

  tags = {
    Name = "sg-nat"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc_all" {
  security_group_id = aws_security_group.sg_nat.id

  description = "Inbound from the VPC to be forwarded out by the NAT instance"
  cidr_ipv4   = aws_vpc.main.cidr_block
  ip_protocol = "-1"
}

#trivy:ignore:AVD-AWS-0104 NAT must forward all VPC egress to the internet
resource "aws_vpc_security_group_egress_rule" "nat_egress_all" {
  security_group_id = aws_security_group.sg_nat.id

  description = "Outbound to the internet for NAT forwarding"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1" # semantically equivalent to all ports
}
