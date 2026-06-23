#!/bin/bash
# ============================================================
# 모니터링 인스턴스 초기화 스크립트 (User Data)
# Amazon Linux 2023 전용
# ============================================================
set -euo pipefail

LOG_FILE="/var/log/monitoring-init.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "[$(date)] 모니터링 인스턴스 초기화 시작"
echo "=========================================="

# ---- 1. 시스템 업데이트 ----
echo "[$(date)] 시스템 패키지 업데이트..."
dnf update -y

# ---- 2. 필수 패키지 설치 ----
echo "[$(date)] 필수 패키지 설치..."
dnf install -y docker git jq curl wget unzip

# ---- 3. Docker 설정 및 시작 ----
echo "[$(date)] Docker 서비스 시작..."
systemctl enable docker
systemctl start docker

# ec2-user를 docker 그룹에 추가
usermod -aG docker ec2-user

# ---- 4. Docker Compose v2 설치 ----
echo "[$(date)] Docker Compose 설치..."
DOCKER_COMPOSE_VERSION="v2.29.1"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# docker compose 명령어 확인
docker compose version

# ---- 5. 데이터 볼륨 마운트 (/dev/xvdf → /data) ----
echo "[$(date)] 데이터 볼륨 설정..."
DATA_DEVICE="/dev/xvdf"
DATA_MOUNT="/data"

# 디바이스가 연결될 때까지 대기 (최대 60초)
WAIT_COUNT=0
while [ ! -b "$DATA_DEVICE" ] && [ $WAIT_COUNT -lt 60 ]; do
  echo "  데이터 볼륨 연결 대기 중... ($WAIT_COUNT/60)"
  sleep 1
  WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ -b "$DATA_DEVICE" ]; then
  # 파일시스템이 없으면 생성
  if ! blkid "$DATA_DEVICE" | grep -q "TYPE="; then
    echo "  파일시스템 생성 (xfs)..."
    mkfs.xfs "$DATA_DEVICE"
  fi

  mkdir -p "$DATA_MOUNT"
  mount "$DATA_DEVICE" "$DATA_MOUNT"

  # /etc/fstab에 영구 마운트 등록
  UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
  if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID $DATA_MOUNT xfs defaults,nofail 0 2" >> /etc/fstab
  fi

  # Docker 데이터 디렉토리 생성
  mkdir -p "$DATA_MOUNT/prometheus"
  mkdir -p "$DATA_MOUNT/loki"
  mkdir -p "$DATA_MOUNT/grafana"
  chown -R 65534:65534 "$DATA_MOUNT/prometheus"  # nobody user (prometheus)
  chown -R 10001:10001 "$DATA_MOUNT/loki"         # loki user
  chown -R 472:472 "$DATA_MOUNT/grafana"           # grafana user

  echo "  데이터 볼륨 마운트 완료: $DATA_MOUNT"
else
  echo "  ⚠️ 데이터 볼륨을 찾을 수 없습니다. 로컬 스토리지를 사용합니다."
  mkdir -p /data/{prometheus,loki,grafana}
  chown -R 65534:65534 /data/prometheus
  chown -R 10001:10001 /data/loki
  chown -R 472:472 /data/grafana
fi

# ---- 6. 프로젝트 디렉토리 생성 ----
echo "[$(date)] 프로젝트 디렉토리 생성..."
PROJECT_DIR="/opt/${project_name}"
mkdir -p "$PROJECT_DIR"
chown ec2-user:ec2-user "$PROJECT_DIR"

# ---- 7. Node Exporter 설치 (모니터링 인스턴스 자체 메트릭) ----
echo "[$(date)] Node Exporter 설치..."
NODE_EXPORTER_VERSION="1.8.2"
cd /tmp
wget -q "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VERSION}/node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
mv "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
rm -rf "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64"*

# Node Exporter 전용 사용자 생성
useradd -rs /bin/false node_exporter 2>/dev/null || true

# systemd 서비스 등록
cat > /etc/systemd/system/node_exporter.service <<'NODEEOF'
[Unit]
Description=Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
Restart=on-failure
RestartSec=5
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes

[Install]
WantedBy=multi-user.target
NODEEOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

echo "=========================================="
echo "[$(date)] 모니터링 인스턴스 초기화 완료!"
echo "=========================================="
echo "  Docker:         $(docker --version)"
echo "  Docker Compose: $(docker compose version)"
echo "  Node Exporter:  $(node_exporter --version 2>&1 | head -1)"
echo "  데이터 볼륨:    $DATA_MOUNT"
echo "  프로젝트 경로:  $PROJECT_DIR"
echo "=========================================="
