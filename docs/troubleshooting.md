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
