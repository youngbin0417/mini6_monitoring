# 🏗️ 아키텍처 상세 문서

## 전체 아키텍처

PLG 스택(Prometheus + Loki + Grafana)을 EC2 인스턴스에 Docker Compose로 배포하는 구조입니다.

### 구성 요소

| 컴포넌트          | 역할                              | 포트 | 이미지 버전 |
| :---------------- | :-------------------------------- | :--- | :---------- |
| **Prometheus**    | 메트릭 수집 및 시계열 데이터 저장 | 9090 | v2.53.0     |
| **Loki**          | 로그 수집 및 인덱싱               | 3100 | 3.1.0       |
| **Grafana**       | 시각화 대시보드                   | 3000 | 11.1.0      |
| **Node Exporter** | 시스템 메트릭 노출                | 9100 | 1.8.2       |

### 데이터 흐름

```
메트릭 흐름 (Pull 방식):
  Node Exporter(:9100) → Prometheus(:9090) → Grafana(:3000)

로그 흐름 (Push 방식):
  Promtail → Loki(:3100) → Grafana(:3000)
```

## 네트워크 구성

### VPC 설계

| 리소스          | CIDR        | 설명        |
| :-------------- | :---------- | :---------- |
| VPC             | 10.0.0.0/16 | 전체 네트워크 |
| Public Subnet A | 10.0.1.0/24 | us-east-1a  |
| Public Subnet B | 10.0.2.0/24 | us-east-1c  |

### Security Group 규칙 (모니터링 인스턴스)

| 방향     | 포트 | 프로토콜 | 소스      | 용도             |
| :------- | :--- | :------- | :-------- | :--------------- |
| Inbound  | 22   | TCP      | 관리자 IP | SSH              |
| Inbound  | 3000 | TCP      | 관리자 IP | Grafana          |
| Inbound  | 9090 | TCP      | 관리자 IP | Prometheus       |
| Inbound  | 3100 | TCP      | VPC CIDR  | Loki (로그 수신) |
| Inbound  | 9100 | TCP      | VPC CIDR  | Node Exporter    |
| Outbound | ALL  | ALL      | 0.0.0.0/0 | 인터넷 접근      |

## 스토리지 설계

### EBS 볼륨 구성

| 볼륨   | 마운트 | 크기 | 타입 | 용도                               |
| :----- | :----- | :--- | :--- | :--------------------------------- |
| 루트   | /      | 20GB | gp3  | OS + Docker                        |
| 데이터 | /data  | 50GB | gp3  | Prometheus + Loki + Grafana 데이터 |

### 데이터 디렉토리 구조

```
/data/
├── prometheus/    # Prometheus TSDB (uid: 65534, nobody)
├── loki/          # Loki chunks + WAL (uid: 10001, loki)
└── grafana/       # Grafana 설정 + 플러그인 (uid: 472, grafana)
```

## 확장 포인트

### 서비스 인스턴스 추가 시

1. `terraform/ec2_services.tf` 파일 생성 (별도 분리)
2. `prometheus/prometheus.yml`에 Node Exporter 타겟 추가
3. 서비스 인스턴스에서 `scripts/install-agents.sh` 실행
4. `curl -X POST http://localhost:9090/-/reload`로 설정 적용

### Alertmanager 연동 시

1. `docker-compose.yml`에 Alertmanager 서비스 추가
2. `prometheus.yml`에 alerting 섹션 추가
3. Alertmanager 설정 파일 (Slack/Email 수신자 설정)

### Bedrock AI 연동 시

1. Lambda 함수 또는 API 서버 구현
2. Loki API로 로그 데이터 조회
3. Bedrock Claude 모델에 분석 요청
4. Grafana 패널에 결과 표시
