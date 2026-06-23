# ============================================================
# 입력 변수 정의 (모니터링 인스턴스 전용)
# ============================================================

# ---- AWS 기본 설정 ----
variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "환경 구분 (dev / staging / prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "프로젝트 이름 (리소스 네이밍에 사용)"
  type        = string
  default     = "aivle05-monitoring"
}

# ---- VPC 설정 ----
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 블록 목록"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "사용할 가용 영역"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1c"]
}

# ---- EC2 모니터링 인스턴스 설정 ----
variable "monitoring_instance_type" {
  description = "모니터링 인스턴스 타입 (최소 t3.small, 권장 t3.medium)"
  type        = string
  default     = "t3.medium"
}

variable "monitoring_ami_id" {
  description = "모니터링 인스턴스 AMI ID (Amazon Linux 2023 권장). 비워두면 최신 Amazon Linux 2023 자동 선택"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "EC2 접속용 SSH Key Pair 이름 (기존 키 사용 시 입력)"
  type        = string
  default     = ""
}

variable "create_key_pair" {
  description = "새로운 Key Pair를 생성할지 여부 (key_pair_name이 비어있을 때 사용)"
  type        = bool
  default     = true
}

variable "monitoring_root_volume_size" {
  description = "모니터링 인스턴스 루트 볼륨 크기 (GB)"
  type        = number
  default     = 20
}

variable "monitoring_data_volume_size" {
  description = "모니터링 데이터 볼륨 크기 (GB) - Prometheus/Loki 데이터 저장"
  type        = number
  default     = 50
}

# ---- 접근 제어 ----
variable "allowed_ssh_cidrs" {
  description = "SSH 접속을 허용할 CIDR 블록 목록"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # 프로덕션에서는 특정 IP로 제한할 것
}

variable "allowed_grafana_cidrs" {
  description = "Grafana 접속을 허용할 CIDR 블록 목록"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # 프로덕션에서는 VPN/사내 IP로 제한할 것
}

# ---- 서비스 인스턴스 연동용 (추후 사용) ----
variable "service_instance_cidrs" {
  description = "서비스 인스턴스들이 속한 CIDR 블록 (Node Exporter/Promtail 통신 허용)"
  type        = list(string)
  default     = ["10.0.0.0/16"]  # 같은 VPC 내 모든 인스턴스 허용
}
