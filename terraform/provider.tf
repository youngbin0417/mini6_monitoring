# ============================================================
# Terraform Provider 설정
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 로컬 백엔드 (추후 S3 백엔드로 전환 가능)
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mini6-monitoring"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
