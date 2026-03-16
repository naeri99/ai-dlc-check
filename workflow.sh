#!/bin/bash

# ============================================================
# AI-DLC 전체 환경 구성 워크플로우
# 실행 순서: Docker → Python/Node 환경 → npm 설정 →
#            Docker 이미지 → TypeScript 프로젝트 →
#            PostgreSQL → Elasticsearch → MCP 서버
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()     { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${BLUE}══════════════════════════════════════════════════${NC}"; \
            echo -e "${BLUE}  $1${NC}"; \
            echo -e "${BLUE}══════════════════════════════════════════════════${NC}"; }

FAILED_STEPS=()

run_step() {
    local step_num="$1"
    local step_name="$2"
    local cmd="$3"

    section "[$step_num] $step_name"

    if eval "$cmd"; then
        log "$step_name 완료"
    else
        error "$step_name 실패 (종료 코드: $?)"
        FAILED_STEPS+=("[$step_num] $step_name")
        # 치명적 단계(Docker, Python/Node)는 중단, 나머지는 계속 진행
        if [ "$4" = "critical" ]; then
            error "치명적 오류 - 워크플로우를 중단합니다."
            exit 1
        fi
        warn "이 단계를 건너뛰고 계속합니다..."
    fi
}

# ──────────────────────────────────────────────────────────
# 사전 점검
# ──────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      AI-DLC 전체 환경 구성 워크플로우 시작        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
log "스크립트 디렉토리: $SCRIPT_DIR"
log "실행 사용자: $(whoami)"

# ──────────────────────────────────────────────────────────
# STEP 1: Docker 설치
#   - docker가 이미 설치된 경우 건너뜀
#   - 설치가 필요한 경우 root 권한 필요 (sudo 사용)
# ──────────────────────────────────────────────────────────
section "[1/8] Docker 설치 확인"

if command -v docker &>/dev/null && docker --version &>/dev/null; then
    log "Docker가 이미 설치되어 있습니다: $(docker --version)"
else
    warn "Docker가 설치되어 있지 않습니다. 설치를 시작합니다..."
    if [ "$EUID" -ne 0 ]; then
        warn "Docker 설치는 root 권한이 필요합니다. sudo로 실행합니다..."
        if ! sudo bash "$SCRIPT_DIR/install-docker.sh"; then
            error "Docker 설치 실패"
            FAILED_STEPS+=("[1/8] Docker 설치")
            error "Docker 없이는 PostgreSQL/Elasticsearch/MCP를 배포할 수 없습니다."
            error "sudo bash $SCRIPT_DIR/install-docker.sh 를 먼저 실행 후 재시도하세요."
            exit 1
        fi
    else
        if ! bash "$SCRIPT_DIR/install-docker.sh"; then
            error "Docker 설치 실패"
            exit 1
        fi
    fi
    log "Docker 설치 완료: $(docker --version)"
fi

# Docker 데몬 실행 확인
if ! docker info &>/dev/null; then
    warn "Docker 데몬이 실행 중이지 않습니다. 시작을 시도합니다..."
    if command -v systemctl &>/dev/null; then
        sudo systemctl start docker || true
        sleep 3
    fi
    if ! docker info &>/dev/null; then
        error "Docker 데몬 시작 실패. 수동으로 'sudo systemctl start docker' 실행 후 재시도하세요."
        exit 1
    fi
fi
log "Docker 데몬 정상 실행 중"

# ──────────────────────────────────────────────────────────
# STEP 2: Python 3.12 + uv + 패키지 설치
#   - Python 환경 (elasticsearch, psycopg2, strands-agents 등)
#   - Node.js + TypeScript 서버 패키지 포함
# ──────────────────────────────────────────────────────────
run_step "2/8" "Python 3.12 + uv + 패키지 설치" \
    "bash '$SCRIPT_DIR/install-uv-python312.sh'" \
    "critical"

# PATH에 uv 경로 추가 (현재 세션 즉시 적용)
export PATH="$HOME/.local/bin:$PATH"

# ──────────────────────────────────────────────────────────
# STEP 3: npm 글로벌 설정 + Docker 이미지 사전 pull
#   - npm global prefix 설정 (sudo 없이 npm -g 사용 가능하게)
#   - node:20-alpine, node:20-slim, nginx:alpine 등 pull
#   - Docker가 이미 설치/실행 중임을 확인했으므로 정상 동작
# ──────────────────────────────────────────────────────────
run_step "3/8" "npm 글로벌 설정 + Docker 이미지 pull" \
    "bash '$SCRIPT_DIR/install-npm-global.sh'"

# npm global PATH 현재 세션에 즉시 적용
export PATH="$HOME/.npm-global/bin:$PATH"

# ──────────────────────────────────────────────────────────
# STEP 4: Node.js Docker 이미지 pull
#   - node:20-alpine 이미지 확보
#   - install-npm-global.sh에서 이미 pull했을 수 있으나
#     MCP 서버 빌드(step 8)에 반드시 필요하므로 재확인
# ──────────────────────────────────────────────────────────
run_step "4/8" "Node Docker 이미지 pull (node:20-alpine)" \
    "bash '$SCRIPT_DIR/pull-node-image.sh'"

# ──────────────────────────────────────────────────────────
# STEP 5: TypeScript 프로젝트 환경 구성
#   - Node.js가 이미 설치된 상태 (step 2에서 설치됨)
#   - ts-app/ 프로젝트 생성 (express, pg, @elastic/elasticsearch 등)
#   - 이미 ts-app/ 폴더가 존재하면 덮어쓰기됨
# ──────────────────────────────────────────────────────────
section "[5/8] TypeScript 프로젝트 환경 구성"

if [ -d "$SCRIPT_DIR/ts-app/node_modules" ]; then
    warn "ts-app/node_modules 가 이미 존재합니다. TypeScript 환경 구성을 건너뜁니다."
    warn "재구성하려면 ts-app/ 폴더를 삭제 후 재실행하세요."
else
    if bash "$SCRIPT_DIR/install-typescript-env.sh" "ts-app"; then
        log "TypeScript 프로젝트 환경 구성 완료"
        # install-typescript-env.sh 가 cd "$PROJECT_DIR" 하므로 원래 디렉토리로 복귀
        cd "$SCRIPT_DIR"
    else
        error "TypeScript 환경 구성 실패"
        FAILED_STEPS+=("[5/8] TypeScript 프로젝트 환경 구성")
        warn "이 단계를 건너뛰고 계속합니다..."
        cd "$SCRIPT_DIR"
    fi
fi

# ──────────────────────────────────────────────────────────
# STEP 6: PostgreSQL 컨테이너 배포
#   - Docker 실행 중인 상태 (step 1에서 확인됨)
#   - postgres:16 이미지를 pull 후 컨테이너 시작
#   - --restart always 로 재부팅 시 자동 시작
# ──────────────────────────────────────────────────────────
run_step "6/8" "PostgreSQL 컨테이너 배포" \
    "bash '$SCRIPT_DIR/deploy-postgres.sh'"

# ──────────────────────────────────────────────────────────
# STEP 7: Elasticsearch + Kibana 배포
#   - elasticsearch/ 디렉토리 안에서 실행해야 함
#     (docker build -t es-nori:8.13.0 . 가 해당 경로의 Dockerfile 사용)
#   - docker compose up -d 로 es01, es02 + kibana 시작
#   - nori 한국어 형태소 분석기 플러그인 포함 이미지 빌드
#   - vm.max_map_count=262144 커널 파라미터 설정 (sudo 필요)
# ──────────────────────────────────────────────────────────
section "[7/8] Elasticsearch + Kibana 배포"

ES_DIR="$SCRIPT_DIR/elasticsearch"
if [ ! -d "$ES_DIR" ]; then
    error "elasticsearch/ 디렉토리를 찾을 수 없습니다: $ES_DIR"
    FAILED_STEPS+=("[7/8] Elasticsearch + Kibana 배포")
    warn "이 단계를 건너뜁니다..."
elif [ ! -f "$ES_DIR/deploy.sh" ]; then
    error "elasticsearch/deploy.sh 파일을 찾을 수 없습니다."
    FAILED_STEPS+=("[7/8] Elasticsearch + Kibana 배포")
    warn "이 단계를 건너뜁니다..."
elif [ ! -f "$ES_DIR/Dockerfile" ]; then
    error "elasticsearch/Dockerfile 을 찾을 수 없습니다. Docker 이미지 빌드 불가."
    FAILED_STEPS+=("[7/8] Elasticsearch + Kibana 배포")
    warn "이 단계를 건너뜁니다..."
else
    # deploy.sh 내부에서 sudo systemctl enable docker, sysctl 등을 사용하므로
    # elasticsearch/ 디렉토리로 이동 후 실행
    if (cd "$ES_DIR" && bash deploy.sh); then
        log "Elasticsearch + Kibana 배포 완료"
    else
        error "Elasticsearch + Kibana 배포 실패"
        FAILED_STEPS+=("[7/8] Elasticsearch + Kibana 배포")
        warn "이 단계를 건너뛰고 계속합니다..."
    fi
fi

# ──────────────────────────────────────────────────────────
# STEP 8: MCP 서버 설정 및 시작
#   - PostgreSQL (step 6) + Elasticsearch (step 7) 실행 중이어야 함
#   - node:20-alpine 이미지 기반으로 Docker 빌드
#   - mcp-postgres (port 3100), mcp-elasticsearch (port 3101) 컨테이너 시작
#   - .kiro/settings/mcp.json 자동 생성
# ──────────────────────────────────────────────────────────
section "[8/8] MCP 서버 설정"

# PostgreSQL 실행 확인
PG_RUNNING=false
if docker ps --format '{{.Names}}' | grep -q "^postgres-server$"; then
    log "PostgreSQL 컨테이너가 실행 중입니다."
    PG_RUNNING=true
else
    warn "PostgreSQL 컨테이너(postgres-server)가 실행 중이지 않습니다."
    warn "step 6이 실패했거나 컨테이너 이름이 다릅니다."
fi

# Elasticsearch 실행 확인
ES_RUNNING=false
if docker ps --format '{{.Names}}' | grep -q "es01"; then
    log "Elasticsearch 컨테이너(es01)가 실행 중입니다."
    ES_RUNNING=true
else
    warn "Elasticsearch 컨테이너(es01)가 실행 중이지 않습니다."
    warn "step 7이 실패했거나 클러스터가 아직 준비 중일 수 있습니다."
fi

if [ "$PG_RUNNING" = false ] || [ "$ES_RUNNING" = false ]; then
    warn "PostgreSQL 또는 Elasticsearch가 실행 중이지 않습니다."
    warn "MCP 서버는 빌드되지만 연결 오류가 발생할 수 있습니다."
fi

if bash "$SCRIPT_DIR/setup-mcp-servers.sh"; then
    log "MCP 서버 설정 완료"
else
    error "MCP 서버 설정 실패"
    FAILED_STEPS+=("[8/8] MCP 서버 설정")
fi

# ──────────────────────────────────────────────────────────
# 최종 결과 출력
# ──────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              워크플로우 완료 요약                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}  모든 단계가 성공적으로 완료되었습니다!${NC}"
else
    echo -e "${YELLOW}  일부 단계에서 오류가 발생했습니다:${NC}"
    for step in "${FAILED_STEPS[@]}"; do
        echo -e "  ${RED}✗${NC} $step"
    done
fi

echo ""
echo -e "${GREEN}  [서비스 접속 정보]${NC}"
echo "  PostgreSQL     : localhost:5432  (user: admin / pw: 12341234 / db: mydb)"
echo "  Elasticsearch  : http://localhost:9200"
echo "  Kibana         : http://localhost:5601"
echo "  MCP PostgreSQL : http://localhost:3100/sse"
echo "  MCP Elasticsearch: http://localhost:3101/sse"
echo ""
echo -e "${GREEN}  [유용한 명령어]${NC}"
echo "  컨테이너 상태  : docker ps"
echo "  ES 헬스        : curl -s http://localhost:9200/_cluster/health | python3 -m json.tool"
echo "  Python 가상환경: source .venv/bin/activate"
echo "  TS 개발 서버   : cd $SCRIPT_DIR/ts-app && npm run dev"
echo ""
echo -e "${YELLOW}  PATH 즉시 적용 (현재 터미널):${NC}"
echo "  source ~/.bashrc"
echo ""
