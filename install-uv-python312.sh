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

VENV_DIR="${1:-.venv}"

# ──────────────────────────────────────────
# 1. Python 3.12
# ──────────────────────────────────────────
if ! command -v python3.12 &>/dev/null; then
    log "Python 3.12 not found. Installing..."
    if command -v dnf &>/dev/null; then
        sudo dnf install -y python3.12
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update -y
        sudo apt-get install -y python3.12
    else
        error "Unsupported package manager. Install Python 3.12 manually."
    fi
else
    log "Python 3.12 already installed: $(python3.12 --version)"
fi

# ──────────────────────────────────────────
# 2. uv
# ──────────────────────────────────────────
if ! command -v uv &>/dev/null; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
else
    log "uv already installed: $(uv --version)"
fi

# ──────────────────────────────────────────
# 3. Virtual environment (Python 3.12)
# ──────────────────────────────────────────
log "Creating virtual environment at '$VENV_DIR' with Python 3.12..."
uv venv "$VENV_DIR" --python python3.12

# ──────────────────────────────────────────
# 4. Python packages
# ──────────────────────────────────────────
log "Installing Python packages..."

# Elasticsearch client
log "  → elasticsearch"
uv pip install --python "$VENV_DIR/bin/python" elasticsearch

# PostgreSQL client + ORM
log "  → psycopg2-binary, psycopg[binary], sqlalchemy (PostgreSQL)"
uv pip install --python "$VENV_DIR/bin/python" psycopg2-binary "psycopg[binary]" sqlalchemy

# Strands Agents
log "  → strands-agents"
uv pip install --python "$VENV_DIR/bin/python" strands-agents

# FastAPI + server
log "  → fastapi, uvicorn"
uv pip install --python "$VENV_DIR/bin/python" fastapi "uvicorn[standard]"

# Streamlit
log "  → streamlit"
uv pip install --python "$VENV_DIR/bin/python" streamlit

# PDF parsing + text chunking (for RAG)
log "  → pymupdf, langchain-text-splitters (PDF parsing & chunking)"
uv pip install --python "$VENV_DIR/bin/python" pymupdf langchain-text-splitters

# ──────────────────────────────────────────
# 5. Node.js + TypeScript server packages
# ──────────────────────────────────────────
log "Setting up TypeScript server environment..."

if ! command -v node &>/dev/null; then
    log "Node.js not found. Installing..."
    if command -v dnf &>/dev/null; then
        sudo dnf install -y nodejs npm
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y nodejs npm
    else
        warn "Cannot install Node.js automatically. Install it manually."
    fi
else
    log "Node.js already installed: $(node --version)"
fi

if command -v npm &>/dev/null; then
    # npm global prefix를 사용자 홈으로 설정 (sudo 불필요)
    NPM_GLOBAL_DIR="$HOME/.npm-global"
    mkdir -p "$NPM_GLOBAL_DIR"
    npm config set prefix "$NPM_GLOBAL_DIR"
    export PATH="$NPM_GLOBAL_DIR/bin:$PATH"

    log "Installing TypeScript server packages globally..."
    npm install -g typescript ts-node @types/node express @types/express
else
    warn "npm not available. Skipping TypeScript package installation."
fi

# ──────────────────────────────────────────
# Summary
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Python  : $("$VENV_DIR/bin/python" --version)"
echo "  uv      : $(uv --version)"
command -v node &>/dev/null && echo "  Node.js : $(node --version)"
command -v tsc  &>/dev/null && echo "  tsc     : $(tsc --version)"
echo ""
echo "  [Python] Installed packages:"
echo "    - elasticsearch
    - psycopg2-binary, psycopg[binary], sqlalchemy"
echo "    - strands-agents"
echo "    - fastapi, uvicorn"
echo "    - streamlit"
echo "    - pymupdf, langchain-text-splitters"
echo ""
echo "  [TypeScript] Installed packages:"
echo "    - typescript, ts-node, @types/node"
echo "    - express, @types/express"
echo ""
echo "  Activate Python venv:"
echo -e "  ${YELLOW}source $VENV_DIR/bin/activate${NC}"
