# ============================================================
# Grafana 로컬 단독 테스트 스크립트 (Windows PowerShell)
# ============================================================

# 한글 깨짐 방지 (콘솔 출력 인코딩을 UTF-8로 설정)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Docker 데몬 실행 여부 확인
docker info >$null 2>&1
if ($LastExitCode -ne 0) {
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "[오류] Docker Desktop이 실행 중이지 않습니다." -ForegroundColor Red
    Write-Host "Docker Desktop을 먼저 실행한 후 다시 시도해 주세요." -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Red
    Exit 1
}

$ContainerName = "grafana-test"
$Port = 3000

# 2. 기존 실행 중인 테스트 컨테이너 확인 및 제거
$Existing = docker ps -a --filter "name=^/${ContainerName}$" --format "{{.Names}}"
if ($Existing) {
    Write-Host "기존에 존재하던 '$ContainerName' 컨테이너를 정리하는 중..." -ForegroundColor Yellow
    docker stop $ContainerName >$null 2>&1
    docker rm $ContainerName >$null 2>&1
}

# 3. 절대 경로 추출 (PowerShell 내장 $PSScriptRoot 사용)
# 스크립트 위치 기준 상위 디렉터리(프로젝트 루트) 경로 설정
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.FullName
$ProvisioningPath = Join-Path $ProjectRoot "grafana\provisioning"
$DashboardsPath = Join-Path $ProjectRoot "grafana\dashboards"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Grafana 로컬 단독 테스트 컨테이너를 구동합니다." -ForegroundColor Cyan
Write-Host "대시보드 경로: $DashboardsPath" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

# 4. Grafana 컨테이너 실행
docker run -d `
  --name $ContainerName `
  -p "${Port}:3000" `
  -v "${ProvisioningPath}:/etc/grafana/provisioning" `
  -v "${DashboardsPath}:/var/lib/grafana/dashboards" `
  -e GF_SECURITY_ADMIN_PASSWORD=admin `
  -e GF_AUTH_ANONYMOUS_ENABLED=true `
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin `
  grafana/grafana:11.1.0

if ($LastExitCode -eq 0) {
    Write-Host "`nGrafana 컨테이너가 정상적으로 실행되었습니다!" -ForegroundColor Green
    Write-Host "접속 주소: http://localhost:$Port" -ForegroundColor Green
    Write-Host "(익명 Admin 권한이 활성화되어 바로 대시보드를 편집/조회할 수 있습니다.)" -ForegroundColor Gray
    
    # 5. 브라우저로 자동 접속
    Start-Process "http://localhost:$Port"
    
    Write-Host "`n테스트를 종료하고 컨테이너를 삭제하려면 아무 키나 누르세요..." -ForegroundColor Yellow
    $null = [System.Console]::ReadKey($true)
    
    Write-Host "`n테스트 컨테이너 정리 중..." -ForegroundColor Yellow
    docker stop $ContainerName >$null 2>&1
    docker rm $ContainerName >$null 2>&1
    Write-Host "정리 완료!" -ForegroundColor Green
} else {
    Write-Host "[오류] Grafana 컨테이너 기동에 실패했습니다." -ForegroundColor Red
}
