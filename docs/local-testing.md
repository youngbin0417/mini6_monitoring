# Grafana Local Test

**(1, 2, 3번 중 환경에 맞게)**

## 1. PowerShell (Windows)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\test-grafana.ps1
```

## 2. Bash

```bash
chmod +x scripts/test-grafana.sh
./scripts/test-grafana.sh
```

## 3. Manual (Docker CLI)

```powershell
docker run -d `
  --name grafana-test `
  -p 3000:3000 `
  -v "${PWD}/grafana/provisioning:/etc/grafana/provisioning" `
  -v "${PWD}/grafana/dashboards:/var/lib/grafana/dashboards" `
  -e GF_SECURITY_ADMIN_PASSWORD=admin `
  -e GF_AUTH_ANONYMOUS_ENABLED=true `
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin `
  grafana/grafana:11.1.0
```

- URL: http://localhost:3000

## 4. Clean Up

```bash
docker stop grafana-test
docker rm grafana-test
```
