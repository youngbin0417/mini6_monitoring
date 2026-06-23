#!/bin/bash
# ============================================================
# PLG 모니터링 스택 배포 스크립트
# 모니터링 인스턴스에서 실행
# ============================================================
# 사용법:
#   ./scripts/deploy.sh              # 전체 배포 (초기 또는 업데이트)
#   ./scripts/deploy.sh --restart    # 컨테이너 재시작
#   ./scripts/deploy.sh --reload     # Prometheus 설정만 리로드
# ============================================================
set -euo pipefail

# ---- 색상 정의 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---- 설정 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/monitoring-deploy.log"

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo "$1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ---- 사전 검사 ----
check_prerequisites() {
    log "사전 요구사항 확인 중..."

    if ! command -v docker &> /dev/null; then
        error "Docker가 설치되어 있지 않습니다."
        exit 1
    fi
    success "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

    if ! docker compose version &> /dev/null; then
        error "Docker Compose v2가 설치되어 있지 않습니다."
        exit 1
    fi
    success "Docker Compose: $(docker compose version --short)"

    if [ ! -f "$PROJECT_DIR/.env" ]; then
        warn ".env 파일이 없습니다. .env.example을 복사합니다..."
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        warn "⚠️  .env 파일의 비밀번호를 반드시 변경하세요!"
    fi
    success ".env 파일 확인 완료"
}

# ---- 설정 파일 검증 ----
validate_configs() {
    log "설정 파일 검증 중..."

    # Docker Compose 문법 검증
    cd "$PROJECT_DIR"
    if docker compose config --quiet 2>/dev/null; then
        success "docker-compose.yml 검증 통과"
    else
        error "docker-compose.yml에 오류가 있습니다."
        docker compose config
        exit 1
    fi

    # Prometheus 설정 검증 (컨테이너 이용)
    if docker run --rm -v "$PROJECT_DIR/prometheus:/etc/prometheus:ro" \
        prom/prometheus:v2.53.0 promtool check config /etc/prometheus/prometheus.yml 2>/dev/null; then
        success "prometheus.yml 검증 통과"
    else
        warn "Prometheus 설정 검증을 건너뜁니다 (오프라인 모드)"
    fi
}

# ---- 데이터 디렉토리 권한 설정 ----
setup_data_dirs() {
    log "데이터 디렉토리 설정 중..."

    # /data 디렉토리가 없으면 생성
    if [ ! -d "/data" ]; then
        sudo mkdir -p /data/{prometheus,loki,grafana}
        sudo chown -R 65534:65534 /data/prometheus  # prometheus (nobody)
        sudo chown -R 10001:10001 /data/loki         # loki
        sudo chown -R 472:472 /data/grafana           # grafana
        success "데이터 디렉토리 생성 및 권한 설정 완료"
    else
        success "데이터 디렉토리 이미 존재"
    fi
}

# ---- Docker Compose 배포 ----
deploy_stack() {
    log "PLG 스택 배포 중..."
    cd "$PROJECT_DIR"

    # 이미지 Pull
    log "최신 이미지 다운로드 중..."
    docker compose pull

    # 컨테이너 시작 (백그라운드)
    log "컨테이너 시작 중..."
    docker compose up -d --remove-orphans

    # 시작 대기 및 상태 확인
    log "서비스 시작 대기 중 (최대 60초)..."
    local retries=0
    local max_retries=12

    while [ $retries -lt $max_retries ]; do
        sleep 5
        retries=$((retries + 1))

        # 모든 컨테이너가 healthy 상태인지 확인
        local unhealthy
        unhealthy=$(docker compose ps --format json 2>/dev/null | grep -c '"unhealthy"\|"starting"' || true)

        if [ "$unhealthy" -eq 0 ]; then
            success "모든 서비스가 정상 실행 중입니다!"
            break
        fi

        log "  대기 중... ($((retries * 5))초/${max_retries * 5}초)"
    done

    # 최종 상태 출력
    echo ""
    log "=== 서비스 상태 ==="
    docker compose ps
    echo ""
}

# ---- Prometheus 설정 리로드 ----
reload_prometheus() {
    log "Prometheus 설정 리로드 중..."
    if curl -s -X POST http://localhost:9090/-/reload; then
        success "Prometheus 설정이 리로드되었습니다."
    else
        error "Prometheus 리로드 실패. 서비스가 실행 중인지 확인하세요."
        exit 1
    fi
}

# ---- 컨테이너 재시작 ----
restart_stack() {
    log "PLG 스택 재시작 중..."
    cd "$PROJECT_DIR"
    docker compose restart
    success "재시작 완료"
    docker compose ps
}

# ---- 접속 정보 출력 ----
print_access_info() {
    local public_ip
    public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")

    echo ""
    echo "=============================================="
    echo -e "${GREEN}🎉 PLG 모니터링 스택 배포 완료!${NC}"
    echo "=============================================="
    echo -e "  Grafana:    ${BLUE}http://${public_ip}:3000${NC}"
    echo -e "  Prometheus: ${BLUE}http://${public_ip}:9090${NC}"
    echo -e "  Loki:       ${BLUE}http://${public_ip}:3100${NC}"
    echo ""
    echo "  기본 로그인: admin / (설정한 비밀번호)"
    echo "=============================================="
}

# ---- 메인 실행 ----
main() {
    echo "=============================================="
    echo "  PLG 모니터링 스택 배포 스크립트"
    echo "=============================================="

    case "${1:-}" in
        --restart)
            restart_stack
            ;;
        --reload)
            reload_prometheus
            ;;
        *)
            check_prerequisites
            validate_configs
            setup_data_dirs
            deploy_stack
            print_access_info
            ;;
    esac
}

main "$@"
