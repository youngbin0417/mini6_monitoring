# ============================================================
# Security Groups (모니터링 인스턴스 전용)
# ============================================================

# ---- 모니터링 인스턴스 Security Group ----
resource "aws_security_group" "monitoring" {
  name_prefix = "${var.project_name}-monitoring-"
  description = "Security group for PLG monitoring stack"
  vpc_id      = aws_vpc.monitoring.id

  # --- Ingress Rules ---

  # SSH 접속
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Grafana 웹 UI
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_grafana_cidrs
  }

  # Prometheus (내부 + 관리자 접근용)
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_grafana_cidrs
  }

  # Loki - 서비스 인스턴스에서 로그 Push 수신
  ingress {
    description = "Loki Push API (from service instances)"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = var.service_instance_cidrs
  }

  # Node Exporter (모니터링 인스턴스 자체 메트릭)
  ingress {
    description = "Node Exporter (self-monitoring)"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # --- Egress Rules ---

  # 모든 아웃바운드 트래픽 허용
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-monitoring-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}
