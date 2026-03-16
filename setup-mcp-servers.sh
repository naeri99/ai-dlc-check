#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$SCRIPT_DIR/mcp-servers"

POSTGRES_MCP_PORT=3100
ES_MCP_PORT=3101

POSTGRES_URL="postgresql://admin:12341234@localhost:5432/mydb"
ES_URL="http://localhost:9200"

echo -e "${BLUE}=== MCP Server Setup ===${NC}"
echo ""

# Docker 실행 확인
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}[ERROR] Docker가 실행중이지 않습니다. Docker를 먼저 시작해주세요.${NC}"
  exit 1
fi

mkdir -p "$MCP_DIR"

# ─────────────────────────────────────────
# Dockerfile: PostgreSQL MCP
# ─────────────────────────────────────────
cat > "$MCP_DIR/Dockerfile.postgres" << 'EOF'
FROM node:20-alpine
RUN npm install -g supergateway @modelcontextprotocol/server-postgres
EXPOSE 3100
ENV POSTGRES_URL=""
ENV MCP_PORT=3100
CMD sh -c "supergateway \
  --stdio \"npx -y @modelcontextprotocol/server-postgres ${POSTGRES_URL}\" \
  --port ${MCP_PORT} \
  --baseUrl http://localhost:${MCP_PORT} \
  --ssePath /sse \
  --messagePath /message"
EOF

# ─────────────────────────────────────────
# Dockerfile: Elasticsearch MCP
# ─────────────────────────────────────────
cat > "$MCP_DIR/Dockerfile.elasticsearch" << 'EOF'
FROM node:20-alpine
RUN npm install -g supergateway @elastic/mcp-server-elasticsearch
EXPOSE 3101
ENV ES_URL=""
ENV MCP_PORT=3101
CMD sh -c "ES_URL=${ES_URL} supergateway \
  --stdio \"npx -y @elastic/mcp-server-elasticsearch\" \
  --port ${MCP_PORT} \
  --baseUrl http://localhost:${MCP_PORT} \
  --ssePath /sse \
  --messagePath /message"
EOF

# ─────────────────────────────────────────
# docker-compose.yml
# ─────────────────────────────────────────
cat > "$MCP_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  mcp-postgres:
    build:
      context: .
      dockerfile: Dockerfile.postgres
    image: mcp-postgres:local
    container_name: mcp-postgres
    network_mode: host
    environment:
      - POSTGRES_URL=${POSTGRES_URL}
      - MCP_PORT=${POSTGRES_MCP_PORT}
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  mcp-elasticsearch:
    build:
      context: .
      dockerfile: Dockerfile.elasticsearch
    image: mcp-elasticsearch:local
    container_name: mcp-elasticsearch
    network_mode: host
    environment:
      - ES_URL=${ES_URL}
      - MCP_PORT=${ES_MCP_PORT}
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

echo -e "${YELLOW}[1/3] Docker 이미지 빌드 중...${NC}"
docker compose -f "$MCP_DIR/docker-compose.yml" build

echo ""
echo -e "${YELLOW}[2/3] MCP 서버 컨테이너 시작 중...${NC}"
docker compose -f "$MCP_DIR/docker-compose.yml" up -d

echo ""
echo -e "${YELLOW}[3/3] 컨테이너 상태 확인 중...${NC}"
sleep 3
docker compose -f "$MCP_DIR/docker-compose.yml" ps

# ─────────────────────────────────────────
# Kiro MCP 설정 출력
# ─────────────────────────────────────────
KIRO_MCP_DIR="$SCRIPT_DIR/../.kiro/settings"
mkdir -p "$KIRO_MCP_DIR"

cat > "$KIRO_MCP_DIR/mcp.json" << EOF
{
  "mcpServers": {
    "postgres": {
      "type": "sse",
      "url": "http://localhost:${POSTGRES_MCP_PORT}/sse"
    },
    "elasticsearch": {
      "type": "sse",
      "url": "http://localhost:${ES_MCP_PORT}/sse"
    }
  }
}
EOF

echo ""
echo -e "${GREEN}=== 완료 ===${NC}"
echo ""
echo -e "${BLUE}MCP 서버 엔드포인트:${NC}"
echo -e "  PostgreSQL    : http://localhost:${POSTGRES_MCP_PORT}/sse"
echo -e "  Elasticsearch : http://localhost:${ES_MCP_PORT}/sse"
echo ""
echo -e "${BLUE}Kiro MCP 설정 파일 생성됨:${NC}"
echo -e "  ${KIRO_MCP_DIR}/mcp.json"
echo ""
echo -e "${BLUE}유용한 명령어:${NC}"
echo -e "  로그 확인 (postgres)     : docker logs -f mcp-postgres"
echo -e "  로그 확인 (elasticsearch): docker logs -f mcp-elasticsearch"
echo -e "  컨테이너 중지            : docker compose -f ${MCP_DIR}/docker-compose.yml down"
echo -e "  컨테이너 재시작          : docker compose -f ${MCP_DIR}/docker-compose.yml restart"
