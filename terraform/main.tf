# ============================================================
# Terraform 메인 설정
# ============================================================
# 이 파일은 루트 모듈의 진입점입니다.
# 모든 리소스는 개별 .tf 파일에 정의되어 있습니다:
#   - provider.tf        : AWS Provider 및 Terraform 설정
#   - variables.tf       : 입력 변수 정의
#   - vpc.tf             : VPC, 서브넷, IGW
#   - security_groups.tf : 보안 그룹 규칙
#   - ec2_monitoring.tf  : 모니터링 EC2 인스턴스
#   - outputs.tf         : 출력 값

# 추후 서비스 인스턴스 추가 시:
#   - ec2_services.tf    : 서비스 EC2 인스턴스들 (별도 파일로 분리)
