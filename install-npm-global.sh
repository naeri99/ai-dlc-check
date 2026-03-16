#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

NPM_GLOBAL_DIR="$HOME/.npm-global"

# ──────────────────────────────────────────
# 1. npm global prefix를 사용자 홈 디렉토리로 변경
#    (sudo 없이 npm install -g 가능하게)
# ──────────────────────────────────────────
log "Setting npm global prefix to $NPM_GLOBAL_DIR ..."
mkdir -p "$NPM_GLOBAL_DIR"
npm config set prefix "$NPM_GLOBAL_DIR"

# ──────────────────────────────────────────
# 2. PATH에 추가 (~/.bashrc / ~/.zshrc)
# ──────────────────────────────────────────
EXPORT_LINE='export PATH="$HOME/.npm-global/bin:$PATH"'

add_to_profile() {
    local profile="$1"
    if [ -f "$profile" ]; then
        if ! grep -q ".npm-global/bin" "$profile"; then
            echo "" >> "$profile"
            echo "# npm global (user-local)" >> "$profile"
            echo "$EXPORT_LINE" >> "$profile"
            log "Added PATH to $profile"
        else
            log "PATH already set in $profile"
        fi
    fi
}

add_to_profile "$HOME/.bashrc"
add_to_profile "$HOME/.zshrc"

# 현재 세션에 즉시 적용
export PATH="$NPM_GLOBAL_DIR/bin:$PATH"

# ──────────────────────────────────────────
# 3. TypeScript server 패키지 설치
# ──────────────────────────────────────────
log "Installing TypeScript server packages..."
npm install -g typescript ts-node @types/node express @types/express

# ──────────────────────────────────────────
# 4. 프론트엔드 Docker 이미지 미리 pull
# ──────────────────────────────────────────
if command -v docker &>/dev/null; then
    log "Pulling frontend Docker images..."

    IMAGES=(
        "node:20-alpine"          # Node.js 빌드용 (경량)
        "node:20-slim"            # Node.js 빌드용 (slim)
        "nginx:alpine"            # 정적 파일 서빙
        "nginx:stable-alpine"     # Nginx stable
    )

    for image in "${IMAGES[@]}"; do
        log "  → docker pull $image"
        docker pull "$image"
    done

    log "Docker images pulled successfully."
    docker images | grep -E "node|nginx" | awk '{printf "  %-30s %-15s %s\n", $1, $2, $7}'
else
    warn "Docker not found. Skipping image pull. Run install-docker.sh first."
fi

# ──────────────────────────────────────────
# Summary
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  npm global setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  npm prefix : $(npm config get prefix)"
echo "  node       : $(node --version)"
echo "  npm        : $(npm --version)"
command -v tsc     &>/dev/null && echo "  tsc        : $(tsc --version)"
command -v ts-node &>/dev/null && echo "  ts-node    : $(ts-node --version)"
echo ""
echo "  [Pull된 Docker 이미지]"
echo "    - node:20-alpine       (TypeScript 빌드)"
echo "    - node:20-slim         (TypeScript 빌드)"
echo "    - nginx:alpine         (정적 파일 서빙)"
echo "    - nginx:stable-alpine  (Nginx stable)"
echo ""
echo -e "${YELLOW}  현재 터미널에 PATH 즉시 적용:${NC}"
echo -e "  ${YELLOW}source ~/.bashrc${NC}"
