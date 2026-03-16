#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ──────────────────────────────────────────
# Pull 대상 이미지 목록
# ──────────────────────────────────────────

# Node.js 이미지 (TypeScript 앱 / MCP 서버 빌드용)
NODE_IMAGES=(
    "node:20-alpine"   # 경량 Alpine 기반 (MCP 서버 Dockerfile 기본 이미지)
    "node:20-slim"     # Debian slim 기반 (호환성 필요 시)
)

# Python 서버 이미지 (FastAPI / uvicorn 기반 API 서버용)
PYTHON_IMAGES=(
    "python:3.12-slim"    # FastAPI + uvicorn 서버용 (권장, 경량)
    "python:3.12-alpine"  # 최경량 Alpine 기반 (패키지 호환 주의)
)

# Streamlit 이미지
# - 공식 python:3.12-slim 위에 streamlit을 설치하는 방식이 표준이나
#   python:3.12-slim 으로 충분히 커버되므로 별도 태그 없이 동일 이미지 활용
# - 아래는 streamlit 전용 베이스로 자주 사용되는 이미지
STREAMLIT_IMAGES=(
    "python:3.11-slim"  # streamlit 공식 예제 기준 안정 버전
)

# Nginx (정적 파일 서빙 / 리버스 프록시)
NGINX_IMAGES=(
    "nginx:alpine"         # 경량 Nginx
    "nginx:stable-alpine"  # Nginx stable
)

FAILED=()

pull_images() {
    local category="$1"
    shift
    local images=("$@")

    echo ""
    log "=== $category 이미지 pull 시작 ==="
    for image in "${images[@]}"; do
        log "  → docker pull $image"
        if docker pull "$image"; then
            log "  ✔ $image 완료"
        else
            warn "  ✘ $image pull 실패 - 건너뜁니다"
            FAILED+=("$image")
        fi
    done
}

pull_images "Node.js (TypeScript / MCP 서버용)"   "${NODE_IMAGES[@]}"
pull_images "Python 서버 (FastAPI / uvicorn용)"   "${PYTHON_IMAGES[@]}"
pull_images "Python 서버 (Streamlit용)"           "${STREAMLIT_IMAGES[@]}"
pull_images "Nginx (정적 파일 서빙 / 프록시용)"   "${NGINX_IMAGES[@]}"

# ──────────────────────────────────────────
# 결과 요약
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Docker 이미지 Pull 완료${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
echo "  [현재 보유 이미지]"
docker images | grep -E "REPOSITORY|node|python|nginx|streamlit" | awk '{printf "  %-30s %-15s %s\n", $1, $2, $7}'

if [ ${#FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}  [Pull 실패 이미지]${NC}"
    for img in "${FAILED[@]}"; do
        echo -e "  ${RED}✘${NC} $img"
    done
fi

echo ""
echo "  [용도 안내]"
echo "    node:20-alpine      → MCP 서버 Dockerfile 기본 이미지"
echo "    node:20-slim        → TypeScript 앱 빌드 (호환성 필요 시)"
echo "    python:3.12-slim    → FastAPI + uvicorn API 서버"
echo "    python:3.12-alpine  → 최경량 Python 서버 (패키지 호환 주의)"
echo "    python:3.11-slim    → Streamlit 앱 서버"
echo "    nginx:alpine        → 정적 파일 서빙 / 리버스 프록시"
