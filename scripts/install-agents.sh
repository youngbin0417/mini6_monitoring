#!/bin/bash
# ============================================================
# 서비스 인스턴스용 에이전트 설치 스크립트
# Node Exporter + Promtail 설치
# ============================================================
# 사용법:
#   ./scripts/install-agents.sh <모니터링-서버-IP>
#
# 예시:
#   ./scripts/install-agents.sh 10.0.1.100
#   ./scripts/install-agents.sh 52.79.xxx.xxx
#
# ⚠️ 이 스크립트는 서비스 인스턴스에서 실행합니다.
#    모니터링 인스턴스가 아닙니다!
# ============================================================
set -euo pipefail

# ---- 색상 정의 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ---- 인자 검증 ----
if [ -z "${1:-}" ]; then
    echo "사용법: $0 <모니터링-서버-IP>"
    echo "예시:   $0 10.0.1.100"
    exit 1
fi

MONITORING_IP="$1"
HOSTNAME=$(hostname)
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.1.0"

echo "=============================================="
echo "  에이전트 설치 스크립트"
echo "  대상 서버: ${HOSTNAME}"
echo "  모니터링 서버: ${MONITORING_IP}"
echo "=============================================="

# ---- 1. Node Exporter 설치 ----
install_node_exporter() {
    log "Node Exporter v${NODE_EXPORTER_VERSION} 설치 중..."

    if command -v node_exporter &> /dev/null; then
        warn "Node Exporter가 이미 설치되어 있습니다."
        node_exporter --version 2>&1 | head -1
        return
    fi

    cd /tmp
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*

    # 전용 사용자 생성
    sudo useradd -rs /bin/false node_exporter 2>/dev/null || true

    # systemd 서비스 등록
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
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
ExecStart=/usr/local/bin/node_exporter \\
  --collector.systemd \\
  --collector.processes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter

    success "Node Exporter 설치 완료 (포트: 9100)"
}

# ---- 2. Promtail 설치 ----
install_promtail() {
    log "Promtail v${PROMTAIL_VERSION} 설치 중..."

    if command -v promtail &> /dev/null; then
        warn "Promtail이 이미 설치되어 있습니다."
        return
    fi

    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
    unzip -o promtail-linux-amd64.zip
    sudo mv promtail-linux-amd64 /usr/local/bin/promtail
    rm -f promtail-linux-amd64.zip

    # 설정 파일 디렉토리 생성
    sudo mkdir -p /etc/promtail

    # Promtail 설정 파일 생성
    sudo tee /etc/promtail/config.yml > /dev/null <<EOF
# ============================================================
# Promtail 설정 - ${HOSTNAME}
# 모니터링 서버: ${MONITORING_IP}
# ============================================================
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://${MONITORING_IP}:3100/loki/api/v1/push
    tenant_id: ""
    batchwait: 1s
    batchsize: 1048576   # 1MB

scrape_configs:
  # ---- 시스템 로그 ----
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          host: ${HOSTNAME}
          __path__: /var/log/*.log

  # ---- systemd journal 로그 ----
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: journal
        host: ${HOSTNAME}
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'

  # ---- 애플리케이션 로그 (추후 경로 수정) ----
  # - job_name: application
  #   static_configs:
  #     - targets:
  #         - localhost
  #       labels:
  #         job: application
  #         host: ${HOSTNAME}
  #         __path__: /var/log/application/*.log
EOF

    # positions 디렉토리 생성
    sudo mkdir -p /var/lib/promtail

    # systemd 서비스 등록
    sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail Log Agent
Documentation=https://grafana.com/docs/loki/latest/clients/promtail/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable promtail
    sudo systemctl start promtail

    success "Promtail 설치 완료 (→ ${MONITORING_IP}:3100)"
}

# ---- 3. 설치 확인 ----
verify_installation() {
    echo ""
    log "설치 확인 중..."

    # Node Exporter 상태
    if systemctl is-active --quiet node_exporter; then
        success "Node Exporter: 실행 중"
    else
        error "Node Exporter: 실행 실패"
    fi

    # Promtail 상태
    if systemctl is-active --quiet promtail; then
        success "Promtail: 실행 중"
    else
        warn "Promtail: 실행 실패 (모니터링 서버 연결 확인 필요)"
    fi

    # Node Exporter 메트릭 확인
    if curl -s http://localhost:9100/metrics > /dev/null 2>&1; then
        success "Node Exporter 메트릭 수집 정상"
    fi
}

# ---- 메인 실행 ----
main() {
    install_node_exporter
    install_promtail
    verify_installation

    echo ""
    echo "=============================================="
    echo -e "${GREEN}✅ 에이전트 설치 완료!${NC}"
    echo "=============================================="
    echo "  서버: ${HOSTNAME}"
    echo "  Node Exporter: http://localhost:9100"
    echo "  Promtail → http://${MONITORING_IP}:3100"
    echo ""
    echo "  📌 다음 단계:"
    echo "  1. 모니터링 서버의 prometheus.yml에 이 서버 IP 추가"
    echo "  2. Prometheus 설정 리로드:"
    echo "     curl -X POST http://${MONITORING_IP}:9090/-/reload"
    echo "=============================================="
}

main "$@"
