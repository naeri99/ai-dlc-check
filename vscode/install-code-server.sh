#!/bin/bash
set -e

echo "=== VS Code Web (code-server) 설치 스크립트 ==="

# 기본 설정
PORT=8080
PASSWORD="changeme"  # 원하는 비밀번호로 변경하세요

# code-server 설치
echo "[1/3] code-server 설치 중..."
curl -fsSL https://code-server.dev/install.sh | sh

# 설정 파일 생성
echo "[2/3] 설정 파일 생성 중..."
mkdir -p ~/.config/code-server
cat > ~/.config/code-server/config.yaml << EOF
bind-addr: 0.0.0.0:${PORT}
auth: password
password: ${PASSWORD}
cert: false
EOF

echo "[3/3] code-server 시작 중..."
# systemd 사용 가능하면 서비스로 등록, 아니면 백그라운드 실행
if command -v systemctl &> /dev/null && systemctl is-system-running &> /dev/null; then
    sudo systemctl enable --now code-server@$USER
    echo "systemd 서비스로 등록 완료"
else
    nohup code-server > /tmp/code-server.log 2>&1 &
    echo "백그라운드로 실행 완료 (로그: /tmp/code-server.log)"
fi

echo ""
echo "=== 설치 완료 ==="
echo "접속 주소: http://$(curl -s ifconfig.me):${PORT}"
echo "비밀번호: ${PASSWORD}"
echo ""
echo "※ EC2 보안 그룹에서 포트 ${PORT} 인바운드 규칙을 추가하세요"
echo "※ 보안을 위해 PASSWORD를 반드시 변경하세요"
