#!/bin/bash

# ============================================================
# Grafana 로컬 단독 테스트 스크립트 (Bash)
# ============================================================

# 1. Docker 데몬 실행 여부 확인
if ! docker info >/dev/null 2>&1; then
    echo "=========================================================="
    echo -e "\033[0;31m[오류] Docker Desktop이 실행 중이지 않습니다.\033[0m"
    echo -e "\033[0;33mDocker Desktop을 먼저 실행한 후 다시 시도해 주세요.\033[0m"
    echo "=========================================================="
    exit 1
fi

CONTAINER_NAME="grafana-test"
PORT=3000

# 2. 기존 실행 중인 테스트 컨테이너 확인 및 제거
if docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo -e "\033[0;33m기존에 존재하던 '$CONTAINER_NAME' 컨테이너를 정리하는 중...\033[0m"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
fi

# 3. 절대 경로 추출 (스크립트 위치 기준 상위 디렉터리)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROVISIONING_PATH="$PROJECT_ROOT/grafana/provisioning"
DASHBOARDS_PATH="$PROJECT_ROOT/grafana/dashboards"

echo "=========================================================="
echo -e "\033[0;36mGrafana 로컬 단독 테스트 컨테이너를 구동합니다.\033[0m"
echo -e "대시보드 경로: $DASHBOARDS_PATH"
echo "=========================================================="

# 4. Grafana 컨테이너 실행
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$PORT:3000" \
  -v "$PROVISIONING_PATH:/etc/grafana/provisioning" \
  -v "$DASHBOARDS_PATH:/var/lib/grafana/dashboards" \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_AUTH_ANONYMOUS_ENABLED=true \
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
  grafana/grafana:11.1.0

if [ $? -eq 0 ]; then
    echo ""
    echo -e "\033[0;32mGrafana 컨테이너가 정상적으로 실행되었습니다!\033[0m"
    echo -e "\033[0;32m접속 주소: http://localhost:$PORT\033[0m"
    echo -e "(익명 Admin 권한이 활성화되어 바로 대시보드를 편집/조회할 수 있습니다.)"
    echo ""
    
    # OS별 브라우저 열기 시도
    if command -v xdg-open >/dev/null; then
        xdg-open "http://localhost:$PORT"
    elif command -v open >/dev/null; then
        open "http://localhost:$PORT"
    elif command -v start >/dev/null; then
        # Windows Git Bash 환경
        cmd.exe /c start "http://localhost:$PORT"
    fi

    echo -ne "\033[0;33m테스트를 종료하고 컨테이너를 삭제하려면 Enter를 누르세요...\033[0m"
    read -r
    
    echo -e "\n테스트 컨테이너 정리 중..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
    echo -e "\033[0;32m정리 완료!\033[0m"
else
    echo -e "\033[0;31m[오류] Grafana 컨테이너 기동에 실패했습니다.\033[0m"
fi
