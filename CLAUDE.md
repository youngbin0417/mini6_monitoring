# CLAUDE.md — Claude AI 작업 가이드

이 파일은 Claude (Anthropic)가 이 프로젝트에서 작업할 때 읽는 전용 지침입니다.
**AGENTS.md의 모든 규칙이 여기에도 동일하게 적용됩니다.** 아래는 Claude에 특화된 추가 지침입니다.

---

## 작업 원칙

### 계획이 필요한 작업
다음 경우에는 코드 수정 전에 반드시 계획을 먼저 제시하고 승인을 받는다:
- Terraform 리소스 추가/삭제
- `docker-compose.yml` 서비스 추가
- Prometheus scrape 타겟 추가 (서비스 인스턴스 연동)
- 보안 그룹 규칙 변경

### 계획 없이 바로 수행 가능한 작업
- 문서(`docs/`) 수정 및 추가
- 스크립트 버그 수정
- Grafana 대시보드 패널 레이아웃/색상 조정
- `AGENTS.md` / `CLAUDE.md` 업데이트
- `works.log` 항목 추가

---

## 응답 스타일

- 응답은 간결하게 — 불필요한 장문 설명 생략
- 명령어는 코드 블록으로, 파일은 링크로 제시
- 작업 완료 후 변경된 파일 목록과 핵심 사항만 요약
- 한국어로 응답 (기술 용어·명령어는 영어 유지)

---

## 이 프로젝트에서 절대 하지 말 것

```
# 이것들은 금지
- ec2_services.tf 파일 생성
- docker-compose.yml에 로컬 볼륨 경로 추가
- Grafana 대시보드 패널 제목에 이모지 추가
- .env, *.pem, terraform.tfvars 파일 생성
- 이미지 태그에 latest 사용
- 서비스 인스턴스 코드를 모니터링 인스턴스 코드와 혼용
```

---

## works.log 기록 의무

작업 완료 후 **반드시** `works.log` 파일 말미에 항목을 추가한다. Claude가 AI 에이전트로서 단독 또는 사람과 함께 작업한 내역을 모두 포함한다.

```
[YYYY-MM-DD] @사람id + @claude | 작업 요약
  - 변경 파일: ...
  - 세부 내용: ...
```

- `@claude`: AI 단독 작업 시 사용
- `@사람id + @claude`: 사용자와 페어 프로그래밍 시 사용
- 파일은 항상 **기존 내용 아래에 추가** (덮어쓰기 금지)

---

## 현재 프로젝트 상태 (컨텍스트)

- **완료**: 모니터링 인스턴스 전체 인프라 코드 (Terraform + Docker Compose + PLG 설정 + 스크립트 + 문서)
- **미구현 (의도적)**: 서비스 인스턴스 연동 — `prometheus.yml` 타겟 섹션이 주석 처리된 상태가 정상
- **로컬 테스트**: `docker-compose.local.yml` 또는 `scripts/test-grafana.ps1|sh` 사용

## 핵심 파일 위치

| 파일 | 목적 |
| :--- | :--- |
| `docker-compose.yml` | EC2 프로덕션 배포 |
| `docker-compose.local.yml` | 로컬 개발 테스트 |
| `terraform/ec2_monitoring.tf` | 모니터링 EC2 인스턴스 |
| `prometheus/prometheus.yml` | 스크레이프 타겟 설정 |
| `grafana/dashboards/node-exporter-full.json` | 메인 대시보드 |
| `scripts/deploy.sh` | EC2 배포 실행 |
| `scripts/install-agents.sh` | 서비스 인스턴스용 에이전트 설치 (독립) |
| `docs/local-testing.md` | 로컬 테스트 방법 |
| `docs/quickstart.md` | 빠른 시작 가이드 |
