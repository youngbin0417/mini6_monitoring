#!/bin/bash
# ============================================================
# PLG 스택 헬스 체크 스크립트
# ============================================================
# 사용법:
#   ./scripts/health-check.sh          # 전체 상태 확인
#   ./scripts/health-check.sh --json   # JSON 형태 출력
# ============================================================
set -euo pipefail

# ---- 색상 정의 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

JSON_OUTPUT="${1:-}"
RESULTS=()

# ---- 컴포넌트 상태 확인 함수 ----
check_component() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"

    local status_code
    local response_time

    response_time=$( { time curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null; } 2>&1 )
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [ "$status_code" = "$expected" ]; then
        if [ "$JSON_OUTPUT" != "--json" ]; then
            echo -e "  ${GREEN}●${NC} ${name}: ${GREEN}정상${NC} (HTTP ${status_code})"
        fi
        RESULTS+=("{\"name\":\"${name}\",\"status\":\"healthy\",\"code\":${status_code}}")
        return 0
    else
        if [ "$JSON_OUTPUT" != "--json" ]; then
            echo -e "  ${RED}●${NC} ${name}: ${RED}비정상${NC} (HTTP ${status_code})"
        fi
        RESULTS+=("{\"name\":\"${name}\",\"status\":\"unhealthy\",\"code\":${status_code}}")
        return 1
    fi
}

# ---- Docker 컨테이너 상태 ----
check_containers() {
    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "\n${CYAN}━━━ Docker 컨테이너 상태 ━━━${NC}"
    fi

    local containers=("prometheus" "loki" "grafana")
    for container in "${containers[@]}"; do
        local state
        state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
        local health
        health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")

        if [ "$state" = "running" ]; then
            local health_display=""
            if [ "$health" = "healthy" ]; then
                health_display=" (healthy)"
            elif [ "$health" = "unhealthy" ]; then
                health_display=" (unhealthy)"
            fi

            if [ "$JSON_OUTPUT" != "--json" ]; then
                if [ "$health" = "unhealthy" ]; then
                    echo -e "  ${YELLOW}●${NC} ${container}: ${YELLOW}실행 중${health_display}${NC}"
                else
                    echo -e "  ${GREEN}●${NC} ${container}: ${GREEN}실행 중${health_display}${NC}"
                fi
            fi
        else
            if [ "$JSON_OUTPUT" != "--json" ]; then
                echo -e "  ${RED}●${NC} ${container}: ${RED}${state}${NC}"
            fi
        fi
    done
}

# ---- 서비스 엔드포인트 상태 ----
check_endpoints() {
    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "\n${CYAN}━━━ 서비스 엔드포인트 ━━━${NC}"
    fi

    check_component "Prometheus" "http://localhost:9090/-/healthy" || true
    check_component "Loki" "http://localhost:3100/ready" || true
    check_component "Grafana" "http://localhost:3000/api/health" || true
}

# ---- Node Exporter 상태 ----
check_node_exporter() {
    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "\n${CYAN}━━━ Node Exporter ━━━${NC}"
    fi

    check_component "Node Exporter (로컬)" "http://localhost:9100/metrics" || true
}

# ---- 디스크 사용량 ----
check_disk_usage() {
    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "\n${CYAN}━━━ 디스크 사용량 ━━━${NC}"
    fi

    # /data 볼륨 확인
    if mountpoint -q /data 2>/dev/null; then
        local usage
        usage=$(df -h /data | tail -1 | awk '{print $5}' | tr -d '%')
        local total
        total=$(df -h /data | tail -1 | awk '{print $2}')
        local used
        used=$(df -h /data | tail -1 | awk '{print $3}')

        if [ "$JSON_OUTPUT" != "--json" ]; then
            if [ "$usage" -gt 85 ]; then
                echo -e "  ${RED}●${NC} /data: ${RED}${usage}%${NC} 사용 (${used}/${total})"
            elif [ "$usage" -gt 60 ]; then
                echo -e "  ${YELLOW}●${NC} /data: ${YELLOW}${usage}%${NC} 사용 (${used}/${total})"
            else
                echo -e "  ${GREEN}●${NC} /data: ${GREEN}${usage}%${NC} 사용 (${used}/${total})"
            fi
        fi
    else
        if [ "$JSON_OUTPUT" != "--json" ]; then
            echo -e "  ${YELLOW}●${NC} /data: 별도 볼륨 미마운트 (로컬 디스크 사용 중)"
        fi
    fi

    # 루트 볼륨 확인
    local root_usage
    root_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    local root_total
    root_total=$(df -h / | tail -1 | awk '{print $2}')

    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "  ${GREEN}●${NC} /: ${root_usage}% 사용 (전체 ${root_total})"
    fi
}

# ---- Prometheus 타겟 상태 ----
check_prometheus_targets() {
    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "\n${CYAN}━━━ Prometheus 수집 타겟 ━━━${NC}"
    fi

    local targets
    targets=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null || echo "")

    if [ -z "$targets" ]; then
        if [ "$JSON_OUTPUT" != "--json" ]; then
            echo -e "  ${RED}●${NC} Prometheus에 연결할 수 없습니다."
        fi
        return
    fi

    local active_count
    active_count=$(echo "$targets" | jq '.data.activeTargets | length' 2>/dev/null || echo "0")
    local up_count
    up_count=$(echo "$targets" | jq '[.data.activeTargets[] | select(.health=="up")] | length' 2>/dev/null || echo "0")
    local down_count
    down_count=$(echo "$targets" | jq '[.data.activeTargets[] | select(.health=="down")] | length' 2>/dev/null || echo "0")

    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo -e "  전체: ${active_count}개 | ${GREEN}UP: ${up_count}${NC} | ${RED}DOWN: ${down_count}${NC}"

        # 각 타겟 상세 표시
        echo "$targets" | jq -r '.data.activeTargets[] | "  \(.health) | \(.labels.job) | \(.scrapeUrl)"' 2>/dev/null | while read -r line; do
            if echo "$line" | grep -q "^  up"; then
                echo -e "    ${GREEN}●${NC} $(echo "$line" | sed 's/^  up | //')"
            else
                echo -e "    ${RED}●${NC} $(echo "$line" | sed 's/^  down | //')"
            fi
        done
    fi
}

# ---- JSON 출력 ----
print_json() {
    echo "{"
    echo "  \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
    echo "  \"components\": [$(IFS=,; echo "${RESULTS[*]}")]"
    echo "}"
}

# ---- 메인 실행 ----
main() {
    if [ "$JSON_OUTPUT" != "--json" ]; then
        echo ""
        echo "=============================================="
        echo "  PLG 모니터링 스택 헬스 체크"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=============================================="
    fi

    check_containers
    check_endpoints
    check_node_exporter
    check_disk_usage
    check_prometheus_targets

    if [ "$JSON_OUTPUT" = "--json" ]; then
        print_json
    else
        echo -e "\n=============================================="
        echo -e "  헬스 체크 완료"
        echo "=============================================="
    fi
}

main "$@"
