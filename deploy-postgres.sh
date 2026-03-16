#!/bin/bash

# ============================================================
# PostgreSQL Docker 배포 스크립트
# 시스템 재시작 시 자동으로 컨테이너가 재시작됩니다.
# ============================================================

# --- 설정값 (필요에 따라 수정하세요) ---
CONTAINER_NAME="postgres-server"
POSTGRES_VERSION="16"
POSTGRES_USER="admin"
POSTGRES_PASSWORD="12341234"
POSTGRES_DB="mydb"
HOST_PORT="5432"
CONTAINER_PORT="5432"
DATA_VOLUME="postgres_data"

# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Docker 설치 여부 확인
if ! command -v docker &> /dev/null; then
  log_error "Docker가 설치되어 있지 않습니다. 먼저 Docker를 설치해주세요."
  exit 1
fi

# Docker 데몬 실행 여부 확인
if ! docker info &> /dev/null; then
  log_error "Docker 데몬이 실행 중이지 않습니다. Docker를 시작해주세요."
  exit 1
fi

# 이미 실행 중인 컨테이너 처리
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  log_warn "기존 컨테이너 '${CONTAINER_NAME}'이 존재합니다. 제거 후 재배포합니다."
  docker stop "${CONTAINER_NAME}" &> /dev/null
  docker rm   "${CONTAINER_NAME}" &> /dev/null
  log_info "기존 컨테이너 제거 완료."
fi

# 볼륨 생성 (이미 있으면 재사용)
if ! docker volume inspect "${DATA_VOLUME}" &> /dev/null; then
  log_info "데이터 볼륨 '${DATA_VOLUME}' 생성 중..."
  docker volume create "${DATA_VOLUME}"
fi

# PostgreSQL 이미지 풀
log_info "PostgreSQL ${POSTGRES_VERSION} 이미지를 가져오는 중..."
docker pull "postgres:${POSTGRES_VERSION}"

# 컨테이너 실행
# --restart=always : 시스템 재부팅 및 Docker 재시작 시 자동으로 컨테이너 재시작
log_info "PostgreSQL 컨테이너를 시작합니다..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart always \
  -e POSTGRES_USER="${POSTGRES_USER}" \
  -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  -e POSTGRES_DB="${POSTGRES_DB}" \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  -v "${DATA_VOLUME}:/var/lib/postgresql/data" \
  "postgres:${POSTGRES_VERSION}"

# 결과 확인
if [ $? -eq 0 ]; then
  log_info "PostgreSQL 컨테이너가 성공적으로 시작되었습니다."
  echo ""
  echo "============================================================"
  echo "  접속 정보"
  echo "============================================================"
  echo "  Host     : localhost (또는 서버 IP)"
  echo "  Port     : ${HOST_PORT}"
  echo "  Database : ${POSTGRES_DB}"
  echo "  User     : ${POSTGRES_USER}"
  echo "  Password : ${POSTGRES_PASSWORD}"
  echo ""
  echo "  psql 접속 예시:"
  echo "  psql -h localhost -p ${HOST_PORT} -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
  echo "============================================================"
else
  log_error "컨테이너 시작에 실패했습니다."
  exit 1
fi

# 컨테이너 상태 출력
echo ""
log_info "현재 컨테이너 상태:"
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# ============================================================
# 시스템 재부팅 시 Docker 자동 시작 설정
# ============================================================
log_info "Docker 서비스 부팅 자동 시작 설정 중..."

if command -v systemctl &> /dev/null; then
  sudo systemctl enable docker
  log_info "Docker 서비스 자동 시작 등록 완료 (systemctl enable docker)"
else
  log_warn "systemctl을 찾을 수 없습니다. Docker 자동 시작 설정을 수동으로 확인해주세요."
fi

# 컨테이너 restart 정책 확인
RESTART_POLICY=$(docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' "${CONTAINER_NAME}" 2>/dev/null)
echo ""
echo "============================================================"
echo "  재부팅 자동 시작 설정 확인"
echo "============================================================"
echo "  Docker 서비스  : 부팅 시 자동 시작 (systemctl enable)"
echo "  컨테이너 정책  : ${RESTART_POLICY}"
echo ""
echo "  [동작 방식]"
echo "  1. 서버 재부팅 → Docker 서비스 자동 시작"
echo "  2. Docker 시작 → '${CONTAINER_NAME}' 컨테이너 자동 시작"
echo "============================================================"
