#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }

IMAGE="node:20-alpine"

log "Pulling $IMAGE ..."
docker pull "$IMAGE"

echo ""
echo -e "${GREEN}Done!${NC}"
docker images | grep -E "REPOSITORY|node"
