# ============================================================
# Terraform Outputs (모니터링 인스턴스)
# ============================================================

# ---- 모니터링 인스턴스 접속 정보 ----
output "monitoring_public_ip" {
  description = "모니터링 인스턴스 퍼블릭 IP (Elastic IP)"
  value       = aws_eip.monitoring.public_ip
}

output "monitoring_private_ip" {
  description = "모니터링 인스턴스 프라이빗 IP"
  value       = aws_instance.monitoring.private_ip
}

output "monitoring_instance_id" {
  description = "모니터링 인스턴스 ID"
  value       = aws_instance.monitoring.id
}

# ---- 서비스 URL ----
output "grafana_url" {
  description = "Grafana 대시보드 URL"
  value       = "http://${aws_eip.monitoring.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus 웹 UI URL"
  value       = "http://${aws_eip.monitoring.public_ip}:9090"
}

output "loki_url" {
  description = "Loki API URL (Promtail 설정에 사용)"
  value       = "http://${aws_eip.monitoring.public_ip}:3100"
}

# ---- SSH 접속 명령어 ----
output "ssh_command" {
  description = "SSH 접속 명령어"
  value       = var.key_pair_name != "" ? "ssh -i <your-key.pem> ec2-user@${aws_eip.monitoring.public_ip}" : "ssh -i ${var.project_name}-key.pem ec2-user@${aws_eip.monitoring.public_ip}"
}

# ---- Key Pair 정보 ----
output "key_pair_file" {
  description = "생성된 프라이빗 키 파일 경로 (새로 생성한 경우)"
  value       = var.create_key_pair && var.key_pair_name == "" ? local_file.private_key[0].filename : "기존 키 사용: ${var.key_pair_name}"
}

# ---- VPC 정보 (서비스 인스턴스 추가 시 필요) ----
output "vpc_id" {
  description = "VPC ID (서비스 인스턴스 추가 시 사용)"
  value       = aws_vpc.monitoring.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "monitoring_security_group_id" {
  description = "모니터링 인스턴스 Security Group ID"
  value       = aws_security_group.monitoring.id
}
