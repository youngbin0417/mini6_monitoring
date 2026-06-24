# ============================================================
# 모니터링 인스턴스 IAM Role 및 Policy
# Prometheus EC2 Service Discovery + CloudWatch Exporter 용
# ============================================================

# ---- IAM Role (EC2 인스턴스용) ----
resource "aws_iam_role" "monitoring" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---- EC2 Service Discovery 정책 ----
# Prometheus가 EC2 인스턴스 목록을 조회하여 동적 타겟 탐색
resource "aws_iam_role_policy" "ec2_discovery" {
  name = "${var.project_name}-ec2-discovery"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---- CloudWatch 메트릭 조회 정책 ----
# YACE(CloudWatch Exporter)가 ALB/ASG/EC2 CloudWatch 메트릭을 수집
resource "aws_iam_role_policy" "cloudwatch_read" {
  name = "${var.project_name}-cloudwatch-read"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---- 인스턴스 프로파일 ----
# EC2 인스턴스에 IAM Role을 연결하기 위한 프로파일
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.monitoring.name

  tags = {
    Name        = "${var.project_name}-instance-profile"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
