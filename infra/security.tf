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

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_egress_all" {
  security_group_id = aws_security_group.sg_alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1" # semantically equivalent to all ports
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

  ip_protocol = "tcp"
  from_port   = 3000
  to_port     = 3000
}

resource "aws_vpc_security_group_egress_rule" "ec2_egress_all" {
  security_group_id = aws_security_group.sg_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1" # semantically equivalent to all ports
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

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}

resource "aws_vpc_security_group_egress_rule" "rds_egress_all" {
  security_group_id = aws_security_group.sg_rds.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1" # semantically equivalent to all ports
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

  cidr_ipv4   = aws_vpc.main.cidr_block
  ip_protocol = "-1"

}

resource "aws_vpc_security_group_egress_rule" "nat_egress_all" {
  security_group_id = aws_security_group.sg_nat.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1" # semantically equivalent to all ports
}
