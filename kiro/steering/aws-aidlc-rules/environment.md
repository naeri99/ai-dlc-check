## python 사용할때 꼭 uv 활용
```
source /home/ec2-user/kirotest/.venv/bin/activate && uv run python ...
```

## Bedrock 사용
- global.anthropic.claude-sonnet-4-6
- global.anthropic.claude-opus-4-6-v1
- global.anthropic.claude-haiku-4-5-20251001-v1:0 (경량)

---


## strnads SDK 
'''
from strands import Agent
from strands_tools import http_request

# Define a weather-focused system prompt
WEATHER_SYSTEM_PROMPT = """You are a weather assistant with HTTP capabilities. You can:

1. Make HTTP requests to the National Weather Service API
2. Process and display weather forecast data
3. Provide weather information for locations in the United States

When retrieving weather information:
1. First get the coordinates or grid information using https://api.weather.gov/points/{latitude},{longitude} or https://api.weather.gov/points/{zipcode}
2. Then use the returned forecast URL to get the actual forecast

When displaying responses:
- Format weather data in a human-readable way
- Highlight important information like temperature, precipitation, and alerts
- Handle errors appropriately
- Convert technical terms to user-friendly language

Always explain the weather conditions clearly and provide context for the forecast.
"""


# Create an agent with HTTP capabilities
weather_agent = Agent(
    system_prompt=WEATHER_SYSTEM_PROMPT,
    tools=[http_request],  # Explicitly enable http_request tool
)

'''

## Docker 시스템 구성

| 컨테이너 | 이미지 | 포트 | 상태 |
|---------|--------|------|------|
| postgres-server | postgres:16 | 5432 | Up |
| es01 | es-nori:8.13.0 | 9200 | Up (healthy) |
| es02 | es-nori:8.13.0 | 9201 | Up (healthy) |
| kibana | kibana:8.13.0 | 5601 | Up |

---

## 1. PostgreSQL 16

### 접속 정보
| 항목 | 값 |
|------|----|
| host | localhost |
| port | 5432 |
| user | admin |
| password | 12341234 |
| database | mydb |

### 연결 테스트 결과
- **psycopg2** : 성공 (PostgreSQL 16.13)
- **psycopg v3** : 성공 (PostgreSQL 16.13)
- **SQLAlchemy + psycopg2** : 성공

### 연결 코드 예시

**psycopg2 (동기)**
```python
import psycopg2

conn = psycopg2.connect(
    host='localhost', port=5432,
    user='admin', password='12341234', dbname='mydb'
)
cur = conn.cursor()
cur.execute('SELECT version();')
print(cur.fetchone())
conn.close()
```

**psycopg v3 (동기/비동기 지원)**
```python
import psycopg

conn = psycopg.connect(
    host='localhost', port=5432,
    user='admin', password='12341234', dbname='mydb'
)
cur = conn.cursor()
cur.execute('SELECT version();')
print(cur.fetchone())
conn.close()
```

**SQLAlchemy (ORM)**
```python
from sqlalchemy import create_engine, text

engine = create_engine('postgresql+psycopg2://admin:12341234@localhost:5432/mydb')
with engine.connect() as conn:
    result = conn.execute(text('SELECT version()'))
    print(result.fetchone())
```

---

## 2. Elasticsearch 8.13.0 (es-nori 클러스터)

### 클러스터 구성
| 항목 | 값 |
|------|----|
| cluster name | es-cluster |
| 노드 수 | 2개 (es01 master, es02) |
| cluster status | green |
| security | 비활성화 (xpack.security.enabled=false) |
| 플러그인 | analysis-nori 8.13.0 (한국어 형태소 분석) |

### 접속 정보
| 노드 | host | port |
|------|------|------|
| es01 (master) | localhost | 9200 |
| es02 | localhost | 9201 |

### 연결 테스트 결과
- **requests (HTTP 직접)** : 성공 — 클러스터 상태 green, 노드 2개 확인
- **elasticsearch-py v9 고수준 API** : 실패 (클라이언트 v9 ↔ 서버 v8 미디어 타입 헤더 충돌)
- **elasticsearch-py v9 transport.perform_request** : 동작 가능 (저수준 우회)

> **주의**: 설치된 `elasticsearch-py`가 **v9.3.0** 이지만 서버는 **ES 8.13.0**.
> 고수준 API 호출 시 `BadRequestError(400, media_type_header_exception)` 발생.
> **`requests` 라이브러리로 직접 HTTP 요청하는 방식을 권장.**

### 연결 코드 예시

**requests 방식 (권장)**
```python
import requests

BASE_URL = 'http://localhost:9200'  # es02는 9201

# 클러스터 상태 확인
resp = requests.get(f'{BASE_URL}/_cluster/health')
print(resp.json())

# 문서 인덱싱
resp = requests.post(
    f'{BASE_URL}/my-index/_doc',
    json={'title': '테스트', 'content': '한국어 분석'},
    headers={'Content-Type': 'application/json'}
)
print(resp.json())

# 검색
resp = requests.get(
    f'{BASE_URL}/my-index/_search',
    json={'query': {'match': {'content': '한국어'}}},
    headers={'Content-Type': 'application/json'}
)
print(resp.json())
```

**nori 형태소 분석 테스트**
```python
import requests

resp = requests.get(
    'http://localhost:9200/_analyze',
    json={'analyzer': 'nori', 'text': '한국어 형태소 분석 테스트'},
    headers={'Content-Type': 'application/json'}
)
print(resp.json())
```

---

## 3. Kibana 8.13.0

### 접속 정보
| 항목 | 값 |
|------|----|
| URL | http://localhost:5601 |
| 인증 | 없음 (security 비활성화) |

### 연결 테스트 결과
- **requests HTTP** : 성공 (status: available, All services and plugins are available)
- **브라우저 접속** : http://localhost:5601

### 연결 코드 예시
```python
import requests

resp = requests.get('http://localhost:5601/api/status')
data = resp.json()
print('Kibana version:', data['version']['number'])
print('Status:', data['status']['overall']['level'])
```

---

## Python 패키지 요약 (venv: /home/ec2-user/kirotest/.venv, Python 3.12)

| 패키지 | 버전 | 용도 |
|--------|------|------|
| psycopg2-binary | 2.9.11 | PostgreSQL 연결 (v2) |
| psycopg | 3.3.3 | PostgreSQL 연결 (v3, 비동기 지원) |
| psycopg-binary | 3.3.3 | psycopg v3 바이너리 드라이버 |
| sqlalchemy | 2.0.48 | ORM / PostgreSQL |
| elasticsearch | 9.3.0 | ES 클라이언트 (ES8 서버와 버전 불일치 주의) |
| requests | 2.32.5 | HTTP 범용 (ES/Kibana API 직접 호출 권장) |
| httpx | 0.28.1 | 비동기 HTTP |
| httpx-sse | 0.4.3 | SSE 스트리밍 |
