# 🚀 PLG 모니터링 스택 (Prometheus + Loki + Grafana)

AWS EC2 기반 인프라 모니터링 시스템. Docker Compose로 PLG 스택을 운영하고, Terraform으로 인프라를 관리합니다.

## 📐 아키텍처

```
┌─────────────────────────────────────────────────────┐
│              모니터링 전용 EC2 인스턴스                │
│                                                      │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│   │Prometheus│  │   Loki   │  │ Grafana  │          │
│   │  :9090   │  │  :3100   │  │  :3000   │          │
│   └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│        │             │             │                 │
│        └─────────────┼─────────────┘                 │
│                      │                               │
│              Docker Compose                          │
│        ┌─────────────┴─────────────┐                 │
│        │    EBS 데이터 볼륨 (/data)  │                 │
│        └───────────────────────────┘                 │
│                                                      │
│   ┌──────────────┐                                   │
│   │Node Exporter │ ← 자체 서버 메트릭                  │
│   │    :9100     │                                   │
│   └──────────────┘                                   │
└─────────────────────────────────────────────────────┘
         ▲ Pull 메트릭         ▲ Push 로그
         │                     │
┌────────┴──────┐     ┌───────┴───────┐
│ 서비스 인스턴스 │     │ 서비스 인스턴스 │  (추후 연동)
│ Node Exporter │     │   Promtail   │
└───────────────┘     └───────────────┘
```

## ⚡ 빠른 시작

### 사전 요구사항
- AWS CLI 설정 완료 (`aws configure`)
- Terraform >= 1.5
- Git

### 1단계: 인프라 프로비저닝

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars에 실제 값 입력

terraform init
terraform plan
terraform apply
```

### 2단계: 모니터링 인스턴스 접속 및 배포

```bash
# SSH 접속 (terraform output에서 명령어 확인)
ssh -i mini6-monitoring-key.pem ec2-user@<퍼블릭-IP>

# 프로젝트 클론
git clone <repo-url> /opt/mini6-monitoring
cd /opt/mini6-monitoring

# 환경 변수 설정
cp .env.example .env
vi .env  # 비밀번호 변경!

# PLG 스택 배포
chmod +x scripts/*.sh
./scripts/deploy.sh
```

### 3단계: Grafana 접속

```
URL: http://<퍼블릭-IP>:3000
ID:  admin
PW:  (.env에 설정한 비밀번호)
```

## 📁 프로젝트 구조

```
├── terraform/                  # AWS 인프라 (Terraform)
│   ├── provider.tf             #   AWS Provider 설정
│   ├── variables.tf            #   입력 변수
│   ├── vpc.tf                  #   VPC, 서브넷
│   ├── security_groups.tf      #   보안 그룹
│   ├── ec2_monitoring.tf       #   모니터링 EC2
│   ├── outputs.tf              #   출력 값
│   └── user_data/              #   EC2 초기화 스크립트
│
├── docker-compose.yml          # PLG 스택 오케스트레이션
│
├── prometheus/
│   ├── prometheus.yml          # Prometheus 수집 설정
│   └── alert.rules.yml         # 알람 규칙
│
├── loki/
│   └── loki-config.yaml        # Loki 로그 저장 설정
│
├── grafana/
│   ├── provisioning/           # 자동 프로비저닝
│   │   ├── datasources/        #   데이터 소스 (Prometheus, Loki)
│   │   └── dashboards/         #   대시보드 설정
│   └── dashboards/             # 대시보드 JSON 파일
│
├── scripts/
│   ├── deploy.sh               # 모니터링 스택 배포
│   ├── backup.sh               # 백업 (설정 + 대시보드 + 스냅샷)
│   ├── health-check.sh         # 전체 헬스 체크
│   └── install-agents.sh       # 서비스 인스턴스 에이전트 설치
│
├── examples/                   # 참고 예제
│   ├── promtail-config.yaml    #   Promtail 설정 예제
│   └── docker-compose.override.yml  # 로컬 개발 오버라이드
│
└── docs/                       # 문서
```

## 🔧 주요 명령어

| 작업 | 명령어 |
|:---|:---|
| PLG 스택 시작 | `docker compose up -d` |
| PLG 스택 중지 | `docker compose down` |
| 로그 확인 | `docker compose logs -f` |
| Prometheus 리로드 | `./scripts/deploy.sh --reload` |
| 전체 재시작 | `./scripts/deploy.sh --restart` |
| 헬스 체크 | `./scripts/health-check.sh` |
| 백업 | `./scripts/backup.sh` |
| S3 백업 | `./scripts/backup.sh --s3 <bucket>` |

## 🔒 보안 체크리스트

- [ ] `.env` 파일의 Grafana 비밀번호 변경
- [ ] `terraform.tfvars`에서 SSH/Grafana 접근 IP 제한
- [ ] EC2 Security Group에서 불필요한 포트 차단
- [ ] Grafana 익명 접근 비활성화 확인

## 📊 데이터 보관

| 서비스 | 보관 기간 | 설정 위치 |
|:---|:---|:---|
| Prometheus | 30일 | `docker-compose.yml` (`--storage.tsdb.retention.time`) |
| Loki | 7일 | `loki/loki-config.yaml` (`retention_period`) |
| Grafana | 영구 | EBS 볼륨 |

## 🚧 향후 확장

- [ ] 서비스 인스턴스 연동 (Node Exporter + Promtail)
- [ ] Alertmanager 연동 (Slack, Email 알림)
- [ ] EKS 전환 시 kube-prometheus-stack
- [ ] Amazon Bedrock AI 로그 분석
- [ ] Thanos/Cortex 장기 보관
