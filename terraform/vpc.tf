# ============================================================
# VPC, 서브넷, 인터넷 게이트웨이, 라우트 테이블
# ============================================================

# ---- VPC ----
resource "aws_vpc" "monitoring" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ---- 퍼블릭 서브넷 (다중 AZ) ----
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.monitoring.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# ---- 인터넷 게이트웨이 ----
resource "aws_internet_gateway" "monitoring" {
  vpc_id = aws_vpc.monitoring.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---- 퍼블릭 라우트 테이블 ----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.monitoring.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.monitoring.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# ---- 라우트 테이블 연결 ----
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
