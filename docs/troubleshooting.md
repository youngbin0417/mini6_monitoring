# 🔧 문제 해결 가이드

## Docker Compose 관련

### 컨테이너가 시작되지 않음

```bash
# 상태 확인
docker compose ps

# 로그 확인
docker compose logs prometheus
docker compose logs loki
docker compose logs grafana
```

### 포트 충돌

```bash
# 사용 중인 포트 확인
sudo ss -tlnp | grep -E '3000|9090|3100'

# 충돌하는 프로세스 종료
sudo kill <PID>
```

### 볼륨 권한 오류

```bash
# Prometheus (nobody:nobody, 65534:65534)
sudo chown -R 65534:65534 /data/prometheus

# Loki (loki:loki, 10001:10001)
sudo chown -R 10001:10001 /data/loki

# Grafana (grafana:grafana, 472:472)
sudo chown -R 472:472 /data/grafana
```

## Prometheus 관련

### 타겟이 DOWN 상태

```bash
# Prometheus 타겟 상태 확인
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl, health, lastError}'

# Node Exporter 직접 확인
curl -s http://localhost:9100/metrics | head -5

# 설정 파일 검증
docker run --rm -v $(pwd)/prometheus:/etc/prometheus:ro \
  prom/prometheus:v2.53.0 promtool check config /etc/prometheus/prometheus.yml
```

### 설정 리로드가 작동하지 않음

```bash
# --web.enable-lifecycle 옵션 확인
docker compose logs prometheus | grep lifecycle

# 수동 리로드
curl -X POST http://localhost:9090/-/reload

# 현재 설정 확인
curl -s http://localhost:9090/api/v1/status/config | jq '.data.yaml' | head -20
```

## Loki 관련

### Promtail 로그가 수신되지 않음

```bash
# Loki ready 상태 확인
curl -s http://localhost:3100/ready

# 로그 쿼리 테스트
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq

# Promtail에서 수동 로그 전송 테스트
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H 'Content-Type: application/json' \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)000000000'","test log message"]]}]}'

# Grafana Explore에서 확인
# → Loki 데이터 소스 선택 → {job="test"} 쿼리
```

### Loki 디스크 부족

```bash
# 디스크 사용량 확인
du -sh /data/loki/*

# 보관 기간 단축 (loki-config.yaml)
# retention_period: 72h  (3일로 줄이기)

# 컨테이너 재시작
docker compose restart loki
```

## Grafana 관련

### 대시보드가 로드되지 않음

```bash
# 프로비저닝 로그 확인
docker compose logs grafana | grep -i provisioning

# 대시보드 파일 권한 확인
ls -la grafana/dashboards/

# 프로비저닝 설정 확인
cat grafana/provisioning/dashboards/dashboard.yaml
```

### 비밀번호 분실

```bash
# Grafana CLI로 비밀번호 재설정
docker exec -it grafana grafana-cli admin reset-admin-password newpassword
```

## 메모리 부족

### 증상
- 컨테이너가 OOM으로 종료됨
- `docker compose logs`에서 `Killed` 메시지

### 해결
```bash
# 시스템 메모리 확인
free -h

# t3.small → t3.medium 업그레이드 권장
# terraform.tfvars에서 인스턴스 타입 변경:
# monitoring_instance_type = "t3.medium"
```

## Terraform 관련

### state 파일 잠금

```bash
# 로컬 state 잠금 해제
terraform force-unlock <LOCK_ID>
```

### 인스턴스 재생성 방지

```bash
# user_data 변경으로 인한 재생성은 lifecycle.ignore_changes로 방지됨
# 수동으로 인스턴스에 접속하여 변경 적용
```

---

## ASG + Promtail 실전 트러블슈팅

> ASG(Auto Scaling Group) 환경에서 에이전트를 운영하며 실제 발생한 문제들을 기록합니다.

### Promtail이 실행 중인데 Loki에 로그가 안 들어옴

**원인 A — config 재생성 후 재시작을 안 함**

`systemctl start`는 이미 실행 중인 서비스에 아무것도 하지 않습니다. config를 바꿔도 메모리에는 이전 config가 그대로입니다.

```bash
sudo systemctl restart promtail    # start 대신 항상 restart
journalctl -u promtail -n 10 --no-pager
```

**원인 B — Loki URL 잘못 설정**

```bash
cat /etc/promtail/config.yml | grep url
# 정상: url: http://<모니터링-사설IP>:3100/loki/api/v1/push
```

**원인 C — 보안 그룹 3100 포트 미개방**

```bash
journalctl -u promtail -n 20 --no-pager
# "context deadline exceeded" → TCP 연결 불가 = 보안 그룹 문제
# "connection refused" → Loki 컨테이너가 안 뜬 상태
```

해결: 모니터링 서버 보안 그룹에 인바운드 TCP 3100, 소스: 서비스 VPC CIDR 추가

---

### 모든 ASG 인스턴스가 Grafana에서 같은 hostname으로 보임

**원인**

`install-agents.sh`가 Promtail config 생성 시 hostname을 **설치 시점에 하드코딩**합니다.
동일 AMI로 만든 인스턴스는 원본 인스턴스의 hostname이 config에 그대로 남습니다.

```yaml
# 잘못된 예 — AMI 굽기 당시 hostname이 박혀 있음
host: ip-172-31-21-34.ec2.internal   # 실제 이 인스턴스는 172-31-40-133인데!
```

**즉시 해결**

```bash
# 현재 hostname 확인
hostname -f

# config 교체 후 재시작
sudo sed -i 's/<기존-hostname>/<현재-hostname>/g' /etc/promtail/config.yml
sudo systemctl restart promtail
```

**근본 해결 (스크립트 수정)**

`install-agents.sh`에서 hostname을 고정 변수가 아닌 실행 시 동적 조회로 변경하고,
이미 설치된 경우에도 config를 항상 재생성하도록 수정합니다:

```bash
# 수정 전
HOSTNAME=$(hostname)

# 수정 후: 설치 시 동적 조회
CURRENT_HOSTNAME=$(hostname -f)
```

---

### 기존 실행 중인 ASG 인스턴스에 에이전트가 없음

**원인**

Launch Template User Data는 인스턴스 **최초 생성 시에만** 실행됩니다.
이미 뜬 인스턴스에는 소급 적용되지 않습니다.

**해결 — 각 인스턴스에 수동 실행**

```bash
curl -O https://raw.githubusercontent.com/youngbin0417/mini6_monitoring/deploy/scripts/install-agents.sh
chmod +x install-agents.sh
./install-agents.sh <모니터링-서버-사설IP>
```

스크립트가 설치 여부를 감지하여 바이너리는 건너뛰고 config만 재생성 후 재시작합니다.

**앞으로 자동화:** ASG Launch Template User Data에 스크립트를 추가하면
신규 인스턴스가 생성될 때 자동으로 에이전트가 설치됩니다.

---

### Prometheus EC2 Service Discovery 미감지

**체크리스트**

1. **EC2 태그 확인** — `Project=aivle05` 태그가 없으면 수집 대상 제외됨

   | Key | Value |
   |:----|:------|
   | Project | aivle05 |
   | Role | backend |
   | Color | blue 또는 green |

2. **IAM Role 확인** — `ec2:DescribeInstances` 권한 없으면 인스턴스 목록 조회 불가

   ```bash
   curl -s http://169.254.169.254/latest/meta-data/iam/info
   # "Code": "Success" → IAM Role 정상 연결
   ```

   해결: AWS 콘솔 → EC2 → 인스턴스 선택 → 작업 → 보안 → IAM 역할 수정
   필요 정책: `AmazonEC2ReadOnlyAccess`, `CloudWatchReadOnlyAccess`

3. **보안 그룹 9100 포트** — 서비스 인스턴스 보안 그룹에 TCP 9100, 소스: 모니터링 VPC CIDR

---

### 빠른 진단 체크리스트

```bash
# 모니터링 서버에서
docker compose ps                           # 모든 컨테이너 Up 확인
curl -s http://localhost:9090/-/healthy     # Prometheus 헬스
curl -s http://localhost:3100/ready         # Loki 헬스
docker compose logs yace --tail=10         # CloudWatch Exporter 에러 여부

# 서비스 인스턴스에서
systemctl is-active node_exporter           # Node Exporter 실행 여부
systemctl is-active promtail                # Promtail 실행 여부
curl -s http://localhost:9100/metrics | head -3   # Node Exporter 메트릭
journalctl -u promtail -n 10 --no-pager    # Promtail 에러 로그
```
