#!/bin/bash
# ============================================================
# PLG 스택 백업 스크립트
# ============================================================
# 사용법:
#   ./scripts/backup.sh               # 로컬 백업
#   ./scripts/backup.sh --s3 mybucket  # S3 업로드 포함
# ============================================================
set -euo pipefail

# ---- 색상 정의 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---- 설정 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_NAME="plg-backup-${TIMESTAMP}"

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# ---- 백업 디렉토리 생성 ----
mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}"

# ---- 1. 설정 파일 백업 ----
backup_configs() {
    log "설정 파일 백업 중..."

    local config_dir="${BACKUP_DIR}/${BACKUP_NAME}/configs"
    mkdir -p "$config_dir"

    # 주요 설정 파일 복사
    cp "$PROJECT_DIR/docker-compose.yml" "$config_dir/"
    cp -r "$PROJECT_DIR/prometheus" "$config_dir/"
    cp -r "$PROJECT_DIR/loki" "$config_dir/"
    cp -r "$PROJECT_DIR/grafana" "$config_dir/"

    # .env 파일 (민감 정보 포함 - 암호화 권장)
    if [ -f "$PROJECT_DIR/.env" ]; then
        cp "$PROJECT_DIR/.env" "$config_dir/"
    fi

    success "설정 파일 백업 완료"
}

# ---- 2. Grafana 대시보드 내보내기 ----
backup_grafana_dashboards() {
    log "Grafana 대시보드 내보내기 중..."

    local dashboard_dir="${BACKUP_DIR}/${BACKUP_NAME}/grafana-dashboards"
    mkdir -p "$dashboard_dir"

    # Grafana API로 대시보드 목록 조회
    local grafana_url="http://localhost:3000"
    local auth="admin:$(grep GRAFANA_ADMIN_PASSWORD "$PROJECT_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo 'admin')"

    # 대시보드 UID 목록 가져오기
    local dashboards
    dashboards=$(curl -s -u "$auth" "${grafana_url}/api/search?type=dash-db" 2>/dev/null || echo "[]")

    if [ "$dashboards" = "[]" ] || [ -z "$dashboards" ]; then
        warn "Grafana에서 대시보드를 가져올 수 없습니다. (Grafana가 실행 중이 아닐 수 있음)"
        return
    fi

    # 각 대시보드 JSON 내보내기
    echo "$dashboards" | jq -r '.[].uid' 2>/dev/null | while read -r uid; do
        if [ -n "$uid" ]; then
            local title
            title=$(echo "$dashboards" | jq -r ".[] | select(.uid==\"$uid\") | .title" 2>/dev/null)
            local safe_title
            safe_title=$(echo "$title" | tr ' /' '_-')

            curl -s -u "$auth" "${grafana_url}/api/dashboards/uid/${uid}" 2>/dev/null \
                > "${dashboard_dir}/${safe_title}.json"

            success "  대시보드 내보내기: ${title}"
        fi
    done

    success "Grafana 대시보드 백업 완료"
}

# ---- 3. Prometheus 스냅샷 ----
backup_prometheus_snapshot() {
    log "Prometheus 스냅샷 생성 중..."

    local snapshot_response
    snapshot_response=$(curl -s -X POST "http://localhost:9090/api/v1/admin/tsdb/snapshot" 2>/dev/null || echo "")

    if echo "$snapshot_response" | jq -e '.status == "success"' &>/dev/null; then
        local snapshot_name
        snapshot_name=$(echo "$snapshot_response" | jq -r '.data.name')
        success "Prometheus 스냅샷 생성: ${snapshot_name}"

        # 스냅샷 데이터 복사
        if [ -d "/data/prometheus/snapshots/${snapshot_name}" ]; then
            cp -r "/data/prometheus/snapshots/${snapshot_name}" \
                "${BACKUP_DIR}/${BACKUP_NAME}/prometheus-snapshot/"
            success "스냅샷 데이터 복사 완료"
        fi
    else
        warn "Prometheus 스냅샷 생성 실패 (관리 API가 비활성화되었거나 서비스가 중지됨)"
    fi
}

# ---- 4. 압축 ----
compress_backup() {
    log "백업 파일 압축 중..."

    cd "$BACKUP_DIR"
    tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}/"
    rm -rf "${BACKUP_NAME}/"

    local size
    size=$(du -sh "${BACKUP_NAME}.tar.gz" | cut -f1)
    success "백업 압축 완료: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz (${size})"
}

# ---- 5. S3 업로드 (선택) ----
upload_to_s3() {
    local bucket="$1"
    log "S3에 백업 업로드 중... (s3://${bucket}/backups/)"

    if ! command -v aws &> /dev/null; then
        error "AWS CLI가 설치되어 있지 않습니다."
        return 1
    fi

    aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
        "s3://${bucket}/backups/${BACKUP_NAME}.tar.gz"

    success "S3 업로드 완료: s3://${bucket}/backups/${BACKUP_NAME}.tar.gz"
}

# ---- 6. 오래된 백업 정리 (30일 이상) ----
cleanup_old_backups() {
    log "30일 이상 오래된 백업 정리 중..."

    local count
    count=$(find "$BACKUP_DIR" -name "plg-backup-*.tar.gz" -mtime +30 2>/dev/null | wc -l)

    if [ "$count" -gt 0 ]; then
        find "$BACKUP_DIR" -name "plg-backup-*.tar.gz" -mtime +30 -delete
        success "${count}개의 오래된 백업 삭제"
    else
        success "삭제할 오래된 백업 없음"
    fi
}

# ---- 메인 실행 ----
main() {
    echo "=============================================="
    echo "  PLG 스택 백업"
    echo "  시작: $(date)"
    echo "=============================================="

    backup_configs
    backup_grafana_dashboards
    backup_prometheus_snapshot
    compress_backup
    cleanup_old_backups

    # S3 업로드 옵션
    if [ "${1:-}" = "--s3" ] && [ -n "${2:-}" ]; then
        upload_to_s3 "$2"
    fi

    echo ""
    echo "=============================================="
    echo -e "${GREEN}✅ 백업 완료!${NC}"
    echo "  파일: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    echo "=============================================="
}

main "$@"
