# AGENTS.md — AI Agent 작업 가이드

이 프로젝트에서 AI 에이전트가 작업할 때 반드시 따라야 하는 제약과 스타일을 정의합니다.

---

## 프로젝트 개요

| 항목 | 내용 |
| :--- | :--- |
| 목적 | AWS EC2 단일 인스턴스 기반 PLG 모니터링 스택 (Prometheus + Loki + Grafana) |
| 현재 범위 | **모니터링 인스턴스만** — 서비스 인스턴스 코드는 이 저장소에 포함하지 않음 |
| 기본 리전 | `ap-northeast-2` (서울) |
| 언어 | 설정 파일 주석은 한국어, 코드 심볼은 영어 |

---

## 절대 금지 사항

### 파일/보안
- `.env`, `terraform.tfvars`, `*.pem`, `*_key`, `*_secret` 파일을 절대 생성하거나 커밋 대상에 포함하지 않는다.
- `0.0.0.0/0` CIDR을 프로덕션 보안 그룹에 추가하는 코드를 작성하지 않는다 (변수 기본값에 이미 있는 것은 주석으로 경고 표시 유지).

### 범위 위반
- 서비스 인스턴스용 Terraform 파일(`ec2_services.tf` 등)을 생성하지 않는다.
- `docker-compose.yml` (EC2 프로덕션용)에 Windows/macOS 로컬 경로를 추가하지 않는다.
- 모니터링 인스턴스 코드와 서비스 인스턴스 코드를 같은 파일에 혼용하지 않는다.

### 스타일
- Grafana 대시보드 JSON(`grafana/dashboards/*.json`)에 이모지를 패널 제목이나 행 제목에 넣지 않는다.
- `docker-compose.yml`에 로컬 테스트용 오버라이드를 추가하지 않는다 — 로컬 전용 파일은 `docker-compose.local.yml`을 사용한다.

---

## 파일 구조 규칙

```
mini6_monitoring/
├── terraform/              # 모니터링 인스턴스 전용 인프라 코드
│   └── user_data/          # EC2 초기화 스크립트 (Amazon Linux 2023 기준)
├── docker-compose.yml      # EC2 프로덕션 전용 (/data/* 볼륨 경로 사용)
├── docker-compose.local.yml # 로컬 테스트 전용 (named volumes 사용)
├── prometheus/             # Prometheus 설정 (서비스 타겟은 주석 처리 상태 유지)
├── loki/                   # Loki 설정 (TSDB v13, 7일 보관)
├── grafana/
│   ├── provisioning/       # 자동 프로비저닝 (datasources, dashboards)
│   └── dashboards/         # 대시보드 JSON (이모지 없음, 고정 색상 팔레트)
├── scripts/
│   ├── deploy.sh           # EC2 배포 전용 (모니터링 인스턴스)
│   ├── backup.sh           # 백업
│   ├── health-check.sh     # 헬스 체크
│   ├── install-agents.sh   # 서비스 인스턴스 에이전트 설치 (독립 파일)
│   ├── test-grafana.ps1    # 로컬 Grafana 단독 테스트 (Windows)
│   └── test-grafana.sh     # 로컬 Grafana 단독 테스트 (Bash)
├── examples/               # 참고 예제 (직접 배포에 사용하지 않음)
└── docs/                   # 문서
```

### 새 파일을 추가할 때
- Terraform 파일: `terraform/` 아래, 목적별로 분리 (`ec2_monitoring.tf` 패턴 유지)
- 배포 스크립트: `scripts/` 아래, `.sh` 확장자, `set -euo pipefail` 필수
- 문서: `docs/` 아래, 한국어 마크다운

---

## 코드 스타일

### Terraform
```hcl
# 상단에 ============ 경계선 주석으로 파일 목적 설명
# ============================================================
# 파일 목적 (한국어)
# ============================================================

# ---- 섹션 구분 ----
```
- 모든 리소스에 `var.project_name`과 `var.environment` 기반 네이밍 적용
- `data "aws_ami"` 는 자동 최신 Amazon Linux 2023 조회 방식 사용 (AMI ID 하드코딩 금지)
- `tls_private_key`로 키 페어 자동 생성 (`create_key_pair` 변수로 on/off)
- 기본 태그: `Project`, `Environment`, `ManagedBy = "terraform"`

### Docker Compose
- 서비스 이미지 버전을 항상 고정 (`latest` 금지)
  - Prometheus: `prom/prometheus:v2.53.0`
  - Loki: `grafana/loki:3.1.0`
  - Grafana: `grafana/grafana:11.1.0`
  - Node Exporter: `prom/node-exporter:v1.8.1`
- 모든 서비스에 `restart: unless-stopped` 적용
- EC2용(`docker-compose.yml`) 데이터 볼륨 경로: `/data/prometheus`, `/data/loki`, `/data/grafana`
- 로컬용(`docker-compose.local.yml`) 데이터 볼륨: named volumes (`prometheus_data:` 등)

### Bash 스크립트
- 첫 줄: `#!/bin/bash`
- 두 번째 줄: `set -euo pipefail`
- `log()`, `success()`, `warn()`, `error()` 헬퍼 함수 패턴 사용 (`deploy.sh` 참고)
- 색상 코드: `RED`, `GREEN`, `YELLOW`, `BLUE`, `NC` 변수로 정의

### Grafana 대시보드 JSON
- `title` 필드에 이모지 금지
- 고정 색상 팔레트만 사용:
  - 파랑(Primary): `#1F60C4`
  - 빨강(Critical): `#C4162A`
  - 주황(Warning): `#FF780A`
  - 초록(Success): `#37872D`
  - 회색(Inactive): `#5D5D5D`
- `gradientMode: "none"`, `fillOpacity: 5~10`
- 범례: 테이블 형식 (`mean`, `max`, `lastNotNull` 표시)
- 기본 시간 범위: `now-3h`

---

## 주요 변수 및 기본값

| 변수 | 기본값 | 위치 |
| :--- | :--- | :--- |
| `aws_region` | `ap-northeast-2` | `terraform/variables.tf` |
| `monitoring_instance_type` | `t3.medium` | `terraform/variables.tf` |
| `monitoring_data_volume_size` | `50` (GB) | `terraform/variables.tf` |
| `PROMETHEUS_RETENTION_TIME` | `30d` | `docker-compose.yml` |
| Loki 보관 기간 | `7d` | `loki/loki-config.yaml` |
| Grafana 포트 | `3000` | `docker-compose.yml` |
| Prometheus 포트 | `9090` | `docker-compose.yml` |
| Loki 포트 | `3100` | `docker-compose.yml` |

---

## 작업 전 체크리스트

새로운 기능을 추가하거나 기존 코드를 수정하기 전에 확인:

1. **범위 확인**: 모니터링 인스턴스 전용인가? 서비스 인스턴스 코드를 혼용하지 않는가?
2. **보안 파일 확인**: 민감 정보가 코드에 하드코딩되지 않는가?
3. **이미지 버전 고정**: `latest` 태그를 사용하지 않는가?
4. **볼륨 경로 분리**: EC2용(`/data/*`)과 로컬용(named volumes)이 올바르게 구분되는가?
5. **Grafana 스타일**: 이모지 없음, 고정 색상 팔레트 준수?

---

## 서비스 인스턴스 연동 (미구현 — 독립 보존)

서비스 인스턴스(Node Exporter, Promtail 설치 대상)와의 연동은 현재 의도적으로 미구현 상태입니다.

- `prometheus/prometheus.yml`의 서비스 타겟 섹션: **주석 처리 상태 유지**
- `scripts/install-agents.sh`: 서비스 인스턴스용 독립 스크립트로 유지
- `examples/promtail-config.yaml`: 참고용 예제, 직접 배포하지 않음

연동 시에는 `prometheus.yml` 주석 해제 후 IP 입력, 또는 `file_sd_configs` 방식 사용.
