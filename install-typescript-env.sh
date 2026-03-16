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

PROJECT_DIR="${1:-ts-app}"

# ──────────────────────────────────────────
# 1. Node.js 확인
# ──────────────────────────────────────────
if ! command -v node &>/dev/null; then
    log "Node.js not found. Installing..."
    if command -v dnf &>/dev/null; then
        sudo dnf install -y nodejs npm
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update -y && sudo apt-get install -y nodejs npm
    else
        error "Cannot install Node.js. Install manually."
    fi
else
    log "Node.js: $(node --version), npm: $(npm --version)"
fi

# ──────────────────────────────────────────
# 2. npm global prefix 설정 (sudo 불필요)
# ──────────────────────────────────────────
NPM_GLOBAL_DIR="$HOME/.npm-global"
mkdir -p "$NPM_GLOBAL_DIR"
npm config set prefix "$NPM_GLOBAL_DIR"
export PATH="$NPM_GLOBAL_DIR/bin:$PATH"

EXPORT_LINE='export PATH="$HOME/.npm-global/bin:$PATH"'
for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ] && ! grep -q ".npm-global/bin" "$profile"; then
        echo "" >> "$profile"
        echo "# npm global (user-local)" >> "$profile"
        echo "$EXPORT_LINE" >> "$profile"
        log "PATH 추가됨: $profile"
    fi
done

# ──────────────────────────────────────────
# 3. 전역 도구 설치
# ──────────────────────────────────────────
log "Installing global TypeScript tools..."
npm install -g \
    typescript \
    ts-node \
    tsx \
    nodemon \
    rimraf

# ──────────────────────────────────────────
# 4. 프로젝트 생성
# ──────────────────────────────────────────
log "Creating project: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# package.json 초기화
npm init -y

# ──────────────────────────────────────────
# 5. 프로젝트 의존성 설치
# ──────────────────────────────────────────
log "Installing dependencies..."

# Web framework
npm install express cors helmet dotenv

# Database clients
npm install pg                     # PostgreSQL
npm install @elastic/elasticsearch # Elasticsearch

# Validation & utilities
npm install zod uuid

# Dev dependencies
npm install -D \
    typescript \
    ts-node \
    tsx \
    nodemon \
    @types/node \
    @types/express \
    @types/cors \
    @types/pg \
    @types/uuid \
    rimraf

# ──────────────────────────────────────────
# 6. tsconfig.json 생성
# ──────────────────────────────────────────
log "Creating tsconfig.json..."
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF

# ──────────────────────────────────────────
# 7. 프로젝트 구조 생성
# ──────────────────────────────────────────
log "Creating project structure..."
mkdir -p src/{routes,controllers,services,models,middlewares,config}

# .env 예시
cat > .env.example << 'EOF'
PORT=3000
NODE_ENV=development

# PostgreSQL
PG_HOST=localhost
PG_PORT=5432
PG_DATABASE=mydb
PG_USER=admin
PG_PASSWORD=12341234

# Elasticsearch
ES_URL=http://localhost:9200
EOF

cp .env.example .env

# src/config/database.ts
cat > src/config/database.ts << 'EOF'
import { Pool } from 'pg';

export const pgPool = new Pool({
  host: process.env.PG_HOST || 'localhost',
  port: Number(process.env.PG_PORT) || 5432,
  database: process.env.PG_DATABASE || 'mydb',
  user: process.env.PG_USER || 'admin',
  password: process.env.PG_PASSWORD || '12341234',
});
EOF

# src/config/elasticsearch.ts
cat > src/config/elasticsearch.ts << 'EOF'
import { Client } from '@elastic/elasticsearch';

export const esClient = new Client({
  node: process.env.ES_URL || 'http://localhost:9200',
});
EOF

# src/app.ts
cat > src/app.ts << 'EOF'
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';

dotenv.config();

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

export default app;
EOF

# src/index.ts
cat > src/index.ts << 'EOF'
import app from './app';

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
EOF

# nodemon.json
cat > nodemon.json << 'EOF'
{
  "watch": ["src"],
  "ext": "ts",
  "ignore": ["src/**/*.spec.ts"],
  "exec": "tsx src/index.ts"
}
EOF

# package.json scripts 업데이트
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
pkg.scripts = {
  'dev': 'nodemon',
  'build': 'rimraf dist && tsc',
  'start': 'node dist/index.js',
  'type-check': 'tsc --noEmit'
};
pkg.main = 'dist/index.js';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
"

# ──────────────────────────────────────────
# 8. Summary
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  TypeScript 프로젝트 환경 구성 완료!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  프로젝트 경로 : $(pwd)"
echo "  Node.js       : $(node --version)"
echo "  TypeScript    : $(./node_modules/.bin/tsc --version)"
echo ""
echo "  [설치된 패키지]"
echo "    Dependencies  : express, cors, helmet, dotenv, pg, @elastic/elasticsearch, zod, uuid"
echo "    DevDependencies: typescript, tsx, nodemon, ts-node, @types/*"
echo ""
echo "  [프로젝트 구조]"
echo "    src/"
echo "    ├── index.ts         (진입점)"
echo "    ├── app.ts           (Express 앱)"
echo "    └── config/"
echo "        ├── database.ts  (PostgreSQL 연결)"
echo "        └── elasticsearch.ts (ES 연결)"
echo ""
echo "  [명령어]"
echo -e "  ${YELLOW}cd $PROJECT_DIR${NC}"
echo -e "  ${YELLOW}npm run dev${NC}        # 개발 서버 (hot reload)"
echo -e "  ${YELLOW}npm run build${NC}      # 프로덕션 빌드"
echo -e "  ${YELLOW}npm run type-check${NC} # 타입 체크"
echo ""
echo "  .env 파일에서 DB 연결 정보를 확인하세요."
