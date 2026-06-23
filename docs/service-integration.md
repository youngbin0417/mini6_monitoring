# 🔗 서비스 인스턴스 연동 가이드

이 문서는 모니터링 대상이 되는 실제 서비스 인스턴스(서버)를 PLG 모니터링 스택과 연동하는 구체적인 방법을 설명합니다.

---

## 1. 개요 및 아키텍처

서비스 인스턴스와 모니터링 서버는 다음과 같이 메트릭(Pull)과 로그(Push)를 주고받습니다.

```
+-----------------------------------+             +----------------------------------+
|      서비스 인스턴스 (Target)     |             |    모니터링 인스턴스 (PLG)       |
|                                   |             |                                  |
|   +---------------------------+   |             |   +--------------------------+   |
|   |  Node Exporter (:9100)    | <------------- |   |  Prometheus (:9090)      |   |
|   +---------------------------+   |   (Pull)    |   +--------------------------+   |
|                                   |             |                                  |
|   +---------------------------+   |             |   +--------------------------+   |
|   |  Promtail Agent           | -------------> |   |  Loki (:3100)            |   |
|   +---------------------------+   |   (Push)    |   +--------------------------+   |
+-----------------------------------+             +----------------------------------+
```

- **메트릭(Node Exporter)**: 서비스 인스턴스의 9100 포트에서 노출하는 CPU, 메모리, 디스크 정보를 Prometheus가 주기적으로 가져갑니다 (Pull).
- **로그(Promtail)**: 서비스 인스턴스의 로그 파일(`/var/log/*.log`) 및 Systemd Journal 로그를 Promtail 에이전트가 읽어 모니터링 인스턴스의 Loki(3100 포트)로 직접 전송합니다 (Push).

---

## 2. Step-by-Step 연동 절차

### Step 1. AWS 보안 그룹(Security Group) 규칙 추가

두 서버 간의 통신이 가능하도록 포트를 개방해야 합니다. AWS Console에서 아래 규칙을 추가하세요.

1. **모니터링 인스턴스 보안 그룹 (Inbound 규칙)**
   - **포트**: `3100` (Loki API)
   - **소스**: `서비스 인스턴스의 사설 IP` (또는 VPC CIDR `10.0.0.0/16`)
   - **설명**: 서비스 인스턴스의 Promtail로부터 로그 수신

2. **서비스 인스턴스 보안 그룹 (Inbound 규칙)**
   - **포트**: `9100` (Node Exporter)
   - **소스**: `모니터링 인스턴스의 사설 IP`
   - **설명**: 모니터링 인스턴스의 Prometheus로부터 메트릭 수집 허용

---

### Step 2. 서비스 인스턴스에 에이전트 설치

서비스 인스턴스에 접속하여 메트릭 및 로그 수집 에이전트를 구성합니다.

1. 모니터링 프로젝트 레포지토리에 포함된 [install-agents.sh](file:///c:/Users/User/Desktop/Project/mini6_monitoring/scripts/install-agents.sh) 파일을 서비스 인스턴스로 전송합니다.
2. 서비스 인스턴스 내부에서 **모니터링 서버의 IP**를 인자로 주어 실행합니다.

   ```bash
   chmod +x install-agents.sh

   # 예: 모니터링 인스턴스의 IP가 10.0.1.100인 경우
   sudo ./install-agents.sh 10.0.1.100
   ```

3. **설치 항목 검증**:
   스크립트 실행 완료 후, 서비스들이 정상 기동되는지 확인합니다.
   ```bash
   sudo systemctl status node_exporter
   sudo systemctl status promtail
   ```

---

### Step 3. 모니터링 인스턴스의 Prometheus 설정 업데이트

모니터링 인스턴스의 Prometheus가 새로 추가된 서비스 인스턴스를 수집하도록 등록합니다.

1. 모니터링 인스턴스의 [prometheus.yml](file:///c:/Users/User/Desktop/Project/mini6_monitoring/prometheus/prometheus.yml) 파일을 수정합니다.

# ============================================================

# 📦 서비스 인스턴스 Node Exporter 추가 (prometheus.yml)

# ============================================================

# # 1) 프론트엔드 서비스

# - job_name: 'aivle05-book-frontend'

# static_configs:

# - targets:

# - '<프론트엔드-인스턴스-IP>:9100'

# labels:

# role: 'frontend'

# instance: 'aivle05-book-frontend'

#

# # 2) 백엔드 서비스

# - job_name: 'aivle05-book-backend'

# static_configs:

# - targets:

# - '<백엔드-인스턴스-IP>:9100'

# labels:

# role: 'backend'

# instance: 'aivle05-book-backend'

3. Prometheus 컨테이너를 재시작하지 않고 설정을 반영하기 위해 **API Reload**를 수행합니다.
   ```bash
   curl -X POST http://localhost:9090/-/reload
   ```

---

## 3. Grafana 모니터링 확인

설정을 모두 마친 후, Grafana 웹 UI(`http://<모니터링-서버-IP>:3000`)에 접속하여 정상 연동을 확인합니다.

### 1. Prometheus 메트릭 수집 확인

- 대시보드 중 **Node Exporter Full** 대시보드를 열어 상단 호스트 선택 옵션에 새로 등록한 `prod-service-01`이 표시되고 메트릭이 정상 조회되는지 확인합니다.
- 혹은 Explore 탭에서 `node_cpu_seconds_total` 등을 쿼리하여 조회할 수도 있습니다.

### 2. Loki 로그 수집 확인

- Explore 메뉴로 이동하여 데이터소스를 **Loki**로 선택합니다.
- 쿼리창에 다음과 같이 입력하여 서비스 인스턴스의 실시간 로그가 수집되는지 확인합니다.
  ```logql
  {host="<서비스-인스턴스-호스트명>", job="system"}
  ```
