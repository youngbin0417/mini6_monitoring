# ============================================================
# 모니터링 전용 EC2 인스턴스
# ============================================================

# ---- 최신 Amazon Linux 2023 AMI 자동 검색 ----
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ---- SSH Key Pair (선택적 생성) ----
resource "tls_private_key" "monitoring" {
  count     = var.create_key_pair && var.key_pair_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "monitoring" {
  count      = var.create_key_pair && var.key_pair_name == "" ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.monitoring[0].public_key_openssh

  tags = {
    Name = "${var.project_name}-key"
  }
}

# 생성된 프라이빗 키를 로컬 파일로 저장
resource "local_file" "private_key" {
  count           = var.create_key_pair && var.key_pair_name == "" ? 1 : 0
  content         = tls_private_key.monitoring[0].private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0400"
}

# ---- 모니터링 EC2 인스턴스 ----
resource "aws_instance" "monitoring" {
  ami                    = var.monitoring_ami_id != "" ? var.monitoring_ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type          = var.monitoring_instance_type
  key_name               = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.monitoring[0].key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.monitoring.id]

  # 루트 볼륨
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.monitoring_root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root"
    }
  }

  # User Data: Docker & Docker Compose 자동 설치
  user_data = templatefile("${path.module}/user_data/monitoring_init.sh", {
    project_name = var.project_name
  })

  tags = {
    Name = "${var.project_name}-server"
    Role = "monitoring"
  }

  # User Data 변경 시 인스턴스 재생성 방지 (수동 적용)
  lifecycle {
    ignore_changes = [user_data]
  }
}

# ---- 데이터 볼륨 (Prometheus/Loki 데이터 저장) ----
resource "aws_ebs_volume" "monitoring_data" {
  availability_zone = aws_instance.monitoring.availability_zone
  size              = var.monitoring_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.project_name}-data"
    Role = "monitoring-data"
  }
}

resource "aws_volume_attachment" "monitoring_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.monitoring_data.id
  instance_id = aws_instance.monitoring.id
}

# ---- Elastic IP (고정 퍼블릭 IP) ----
resource "aws_eip" "monitoring" {
  instance = aws_instance.monitoring.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}
