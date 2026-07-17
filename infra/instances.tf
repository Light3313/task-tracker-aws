data "aws_ami" "al2023_arm" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  owners = ["amazon"]
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
  ami           = data.aws_ami.al2023_arm.id
  instance_type = "t4g.micro"

  primary_network_interface {
    network_interface_id = aws_network_interface.nat.id
  }

  # Пересоздати інстанс при зміні user_data (дефолт = лише stop/start,
  # який НЕ перезапускає user_data, тож нова версія не застосувалась би).
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              dnf install -y iptables-services

              # Увімкнути IP forwarding + persist через reboot (без цього MASQUERADE не пересилає нічого)
              echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
              sysctl --system

              # Первинний інтерфейс на AL2023 = ens5/enX0, а не eth0 -> беремо з default route
              PRIMARY_IF=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)

              # NAT: masquerade вихідного трафіку з приватної підмережі
              iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE

              # Зберегти правила, щоб пережили reboot
              systemctl enable iptables
              service iptables save
              EOF

  tags = {
    Name = "tt-nat"
  }
}
