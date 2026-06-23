# 🧠 AWS Bedrock AI 로그 분석 확장 가이드

이 문서는 Loki에 수집되는 로그 데이터를 AWS Bedrock의 AI 모델(예: Anthropic Claude 3)과 연동하여 **실시간 장애 진단 및 요약 보고서 자동화** 시스템을 구축하는 설계와 구현 방안을 설명합니다.

---

## 1. 연동 아키텍처

Loki에서 감지된 비정상적인 로그(Error/Critical 등)를 AI가 즉각 분석하고 해결 가이드(런북)를 전달하는 파이프라인의 설계 구조입니다.

```
[ Grafana Alert ] 
        │ (Webhook 호출)
        ▼
[ API Gateway / AWS Lambda (Alert Handler) ]
        │ 
        ├─▶ 1. Loki API 호출 (장애 시점 전후 로그 조회)
        │      `GET /loki/api/v1/query_range?query={job="system"} |= "error"`
        │ 
        ├─▶ 2. AWS Bedrock API 호출 (장애 원인 분석 및 해결 방안 제안 요청)
        │      Model: Anthropic Claude 3 (Haiku / Sonnet)
        │ 
        └─▶ 3. 결과 전송 및 저장
               ├─▶ Slack Webhook (실시간 AI 장애 분석 보고서 발송)
               └─▶ DynamoDB 저장 ──▶ Grafana 대시보드 (AI 분석 히스토리 패널 표시)
```

---

## 2. 단계별 구현 및 설정 가이드

### Step 1. AWS IAM 권한 설정 (Lambda 실행 역할)

AWS Lambda 함수가 Bedrock 서비스를 호출할 수 있도록 IAM 역할에 정책을 부여해야 합니다.

* **최소 필요 권한 (IAM Policy)**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-*"
    }
  ]
}
```

---

### Step 2. Lambda 함수 개발 (Python/Node.js 예시)

Loki로부터 특정 에러 알림이 들어왔을 때, Loki API를 조회하여 에러 전후의 로그를 받아온 후 Bedrock을 통해 가이드를 작성하는 Lambda 예시 코드입니다.

#### Python (Boto3) 예시
```python
import json
import os
import urllib3
import boto3

bedrock = boto3.client(service_name='bedrock-runtime', region_name='us-east-1')
http = urllib3.PoolManager()

LOKI_URL = os.environ.get('LOKI_URL') # 예: http://<loki-private-ip>:3100
SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL')

def lambda_handler(event, context):
    # 1. Grafana Alert Webhook에서 에러 키워드 및 타겟 인스턴스 정보 추출
    alert_data = json.loads(event.get('body', '{}'))
    alert_name = alert_data.get('title', 'Unknown Alert')
    host = alert_data.get('dashboardURL', '') # 예시
    
    # 2. Loki API를 호출하여 해당 인스턴스의 에러 로그 원본 15줄 조회
    loki_query = '{job=~".+"} |= "error"'
    url = f"{LOKI_URL}/loki/api/v1/query_range?query={loki_query}&limit=15"
    
    try:
        response = http.request('GET', url)
        loki_logs = json.loads(response.data.decode('utf-8'))
        raw_logs = parse_loki_logs(loki_logs)
    except Exception as e:
        raw_logs = f"Loki 로그를 수집할 수 없습니다: {str(e)}"

    # 3. AWS Bedrock(Claude 3 Haiku) 프롬프트 작성
    prompt_content = f"""
당신은 숙련된 DevOps/SRE 엔지니어입니다.
아래 발생한 알림과 에러 로그를 분석하여 원인 파악 및 해결 방안(Runbook)을 한글로 제시해 주세요.

알림명: {alert_name}
에러 로그:
{raw_logs}

형식:
1. 장애 요약 (한 줄)
2. 예상 원인 (우선순위별 최대 2가지)
3. 조치 권장 단계 (간결한 쉘 명령어 포함)
"""

    # 4. Bedrock 모델 호출
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1000,
        "messages": [
            {
                "role": "user",
                "content": prompt_content
            }
        ]
    })
    
    response = bedrock.invoke_model(
        body=body,
        modelId="anthropic.claude-3-haiku-20240307-v1:0", # 비용 효율적인 Haiku 모델 권장
        contentType="application/json",
        accept="application/json"
    )
    
    response_body = json.loads(response.get('body').read())
    ai_analysis = response_body['content'][0]['text']

    # 5. Slack 등 알림 채널로 AI 보고서 발송
    send_to_slack(alert_name, ai_analysis)
    
    return {
        'statusCode': 200,
        'body': json.dumps({'status': 'success'})
    }

def parse_loki_logs(loki_response):
    logs = []
    results = loki_response.get('data', {}).get('result', [])
    for res in results:
        for val in res.get('values', []):
            logs.append(val[1])
    return "\n".join(logs[-15:])

def send_to_slack(alert_name, analysis):
    payload = {
        "text": f"🚨 *[AI 장애 진단] {alert_name}* 🚨\n\n{analysis}"
    }
    http.request('POST', SLACK_WEBHOOK_URL, 
                 headers={'Content-Type': 'application/json'},
                 body=json.dumps(payload))
```

---

### Step 3. Grafana Alerting Webhook 설정

1. **Grafana 웹 UI** ──▶ **Alerting** ──▶ **Contact points** 메뉴로 이동합니다.
2. `New contact point`를 생성합니다.
   * **Name**: `AWS-Bedrock-Lambda-Handler`
   * **Integration**: `Webhook`
   * **URL**: 생성된 API Gateway / Lambda 함수 URL 입력
3. `Notification policies`에서 특정 중요 알림(예: `severity="critical"`) 발생 시 이 Contact point를 타겟으로 하도록 규칙을 매핑합니다.

---

## 3. Grafana 대시보드 내 AI 리포트 표시 (심화)

AI가 분석한 내역을 Slack 외에 **Grafana 대시보드 안에서 보고 싶을 때** 구성 방법입니다.

1. **분석 내역 저장**: Lambda 분석 완료 시, 분석 텍스트와 장애 일시를 AWS DynamoDB 테이블에 기록합니다.
2. **데이터소스 연동**: Grafana에 `Amazon Athena` 또는 `JSON Datasource` 등을 설치하여 DynamoDB 데이터(또는 S3/REST API 결과)를 쿼리할 수 있도록 등록합니다.
3. **패널 배치**: 대시보드 하단에 **Dynamic Text Panel** 또는 **Table Panel**을 생성하여, 장애 발생 타임라인에 매핑되는 AI 분석 진단서 히스토리를 띄워 시각적 효율을 극대화합니다.
