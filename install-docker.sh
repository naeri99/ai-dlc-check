#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Must run as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash install-docker.sh"
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    error "Cannot detect OS. /etc/os-release not found."
fi

log "Detected OS: $OS $VERSION"

install_docker_ubuntu_debian() {
    log "Removing old Docker versions..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    log "Installing dependencies..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    log "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    log "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$OS $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    log "Installing Docker Engine..."
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_rhel_fedora() {
    log "Removing old Docker versions..."
    yum remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    log "Installing yum-utils..."
    yum install -y yum-utils

    log "Adding Docker repository..."
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    log "Installing Docker Engine..."
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_fedora() {
    log "Removing old Docker versions..."
    dnf remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    log "Installing dnf plugins..."
    dnf install -y dnf-plugins-core

    log "Adding Docker repository..."
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    log "Installing Docker Engine..."
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_amazon_linux() {
    log "Installing Docker via amazon-linux-extras or dnf..."
    if command -v amazon-linux-extras &>/dev/null; then
        amazon-linux-extras install -y docker
    else
        dnf install -y docker
    fi

    log "Installing Docker Compose plugin for Amazon Linux..."
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
}

# Run the correct installer
case "$OS" in
    ubuntu|debian)       install_docker_ubuntu_debian ;;
    centos|rhel)         install_docker_rhel_fedora ;;
    fedora)              install_docker_fedora ;;
    amzn)                install_docker_amazon_linux ;;
    *)                   error "Unsupported OS: $OS. Supported: ubuntu, debian, centos, rhel, fedora, amzn" ;;
esac

# Start and enable Docker (부팅 시 자동 시작)
log "Docker 서비스 시작 및 부팅 자동 시작 설정..."
systemctl start docker
systemctl enable docker
systemctl enable containerd
log "부팅 시 Docker 자동 시작 설정 완료 (systemctl enable docker)"

sudo chmod 777 /var/run/docker.sock

# Add current sudo user to docker group (so docker can be used without sudo)
if [ -n "$SUDO_USER" ]; then
    log "Adding user '$SUDO_USER' to the docker group..."
    usermod -aG docker "$SUDO_USER"
    warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
fi



# Verify installation
log "Verifying Docker installation..."
docker --version
docker compose version

log "Running hello-world test..."
docker run --rm hello-world

echo ""
echo -e "${GREEN}Docker installation complete!${NC}"
echo "  Docker Engine : $(docker --version)"
echo "  Docker Compose: $(docker compose version)"

