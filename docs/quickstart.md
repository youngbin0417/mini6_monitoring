# ⚡ 빠른 시작 가이드

## 사전 요구사항

| 도구 | 최소 버전 | 용도 |
|:---|:---|:---|
| AWS CLI | v2 | AWS 리소스 관리 |
| Terraform | 1.5+ | 인프라 프로비저닝 |
| Git | 2.0+ | 소스 관리 |

## Step 1: 프로젝트 클론

```bash
git clone <repository-url>
cd mini6_monitoring
```

## Step 2: Terraform으로 인프라 생성

```bash
cd terraform

# 변수 파일 생성
cp terraform.tfvars.example terraform.tfvars

# ⚠️ terraform.tfvars 편집
# - allowed_ssh_cidrs: 본인 IP로 제한 권장
# - allowed_grafana_cidrs: 접근 IP 제한 권장
vi terraform.tfvars

# 인프라 생성
terraform init
terraform plan        # 리소스 확인
terraform apply       # 실행 (yes 입력)
```

생성 완료 후 출력 값 확인:
```bash
terraform output
# monitoring_public_ip = "x.x.x.x"
# grafana_url = "http://x.x.x.x:3000"
# ssh_command = "ssh -i mini6-monitoring-key.pem ec2-user@x.x.x.x"
```

## Step 3: 모니터링 인스턴스에 접속

```bash
# Terraform이 생성한 키로 SSH 접속
ssh -i mini6-monitoring-key.pem ec2-user@<퍼블릭-IP>

# User Data 초기화 완료 확인
cloud-init status --wait
# status: done
```

## Step 4: 프로젝트 배포

```bash
# 프로젝트 클론 (인스턴스 안에서)
git clone <repository-url> /opt/mini6-monitoring
cd /opt/mini6-monitoring

# 환경 변수 설정
cp .env.example .env
vi .env  # ⚠️ GRAFANA_ADMIN_PASSWORD를 반드시 변경!

# 배포 실행
chmod +x scripts/*.sh
./scripts/deploy.sh
```

## Step 5: 접속 확인

### Grafana
```
URL: http://<퍼블릭-IP>:3000
ID:  admin
PW:  (.env에 설정한 비밀번호)
```

### Prometheus
```
URL: http://<퍼블릭-IP>:9090
→ Status → Targets에서 수집 상태 확인
```

### 헬스 체크
```bash
./scripts/health-check.sh
```

## 다음 단계

1. **서비스 인스턴스 연동**: `scripts/install-agents.sh` 사용
2. **알림 설정**: Alertmanager 추가
3. **대시보드 커스터마이즈**: Grafana에서 직접 편집 후 JSON 내보내기
