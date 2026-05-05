#!/usr/bin/env bash
set -e

PORT="${PORT:-8388}"
METHOD="${METHOD:-aes-256-gcm}"
CONTAINER_NAME="${CONTAINER_NAME:-ss-server}"
IMAGE_NAME="${IMAGE_NAME:-shadowsocks/shadowsocks-libev}"
INSTALL_DIR="${INSTALL_DIR:-/opt/aws-clash-ss}"

echo "======================================"
echo " AWS EC2 Shadowsocks + Clash Setup"
echo " Port: ${PORT}"
echo " Method: ${METHOD}"
echo " Container: ${CONTAINER_NAME}"
echo " Image: ${IMAGE_NAME}"
echo " Install directory: ${INSTALL_DIR}"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo:"
    echo "sudo bash setup_clash_ss.sh"
    exit 1
fi

mkdir -p "$INSTALL_DIR"

echo "[1/8] Updating apt package list..."
apt update -y

echo "[2/8] Installing required packages..."
apt install -y curl ca-certificates gnupg openssl docker.io

echo "[3/8] Enabling and starting Docker..."
systemctl enable docker
systemctl start docker

echo "[4/8] Generating Shadowsocks password..."
PASSWORD=$(openssl rand -hex 16)

echo "[5/8] Detecting EC2 public IPv4..."

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)

if [ -n "$TOKEN" ]; then
    PUBLIC_IP=$(curl -s \
        -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 || true)
else
    PUBLIC_IP=""
fi

if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="YOUR_EC2_PUBLIC_IP"
fi

echo "[6/8] Removing old Shadowsocks container if it exists..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

echo "[7/8] Starting Shadowsocks container..."

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p ${PORT}:${PORT}/tcp \
    -p ${PORT}:${PORT}/udp \
    -e PASSWORD="$PASSWORD" \
    -e METHOD="$METHOD" \
    -e SERVER_ADDR="0.0.0.0" \
    -e SERVER_PORT="$PORT" \
    -e TIMEOUT="300" \
    -e DNS_ADDRS="1.1.1.1,8.8.8.8" \
    "$IMAGE_NAME"

echo "[8/8] Generating Clash configuration..."

cat > "$INSTALL_DIR/server-info.txt" <<EOF
Server type: Shadowsocks
Server IP: $PUBLIC_IP
Port: $PORT
Cipher: $METHOD
Password: $PASSWORD
Docker container: $CONTAINER_NAME
Docker image: $IMAGE_NAME
EOF

cat > "$INSTALL_DIR/clash.yaml" <<EOF
mixed-port: 7890
allow-lan: false
mode: global
log-level: info

proxies:
  - name: "AWS-SS"
    type: ss
    server: $PUBLIC_IP
    port: $PORT
    cipher: $METHOD
    password: "$PASSWORD"
    udp: true

proxy-groups:
  - name: "GLOBAL"
    type: select
    proxies:
      - AWS-SS
      - DIRECT

rules:
  - MATCH,GLOBAL
EOF

echo ""
echo "======================================"
echo " Setup complete"
echo "======================================"
echo ""

echo "Server information:"
cat "$INSTALL_DIR/server-info.txt"

echo ""
echo "Clash config:"
echo "--------------------------------------"
cat "$INSTALL_DIR/clash.yaml"
echo "--------------------------------------"

echo ""
echo "Docker status:"
docker ps | grep "$CONTAINER_NAME" || true

echo ""
echo "Shadowsocks logs:"
docker logs "$CONTAINER_NAME"

echo ""
echo "Files saved on EC2:"
echo "$INSTALL_DIR/server-info.txt"
echo "$INSTALL_DIR/clash.yaml"

echo ""
echo "Important:"
echo "Make sure your AWS Security Group allows:"
echo "TCP ${PORT} from 0.0.0.0/0"
echo "UDP ${PORT} from 0.0.0.0/0"
echo ""
echo "For SSH, keep port 22 limited to your own IP."

echo ""
echo "======================================"
echo " Download Clash config to your computer"
echo "======================================"
echo ""
echo "Run this command on your local Windows PowerShell or CMD, not inside EC2:"
echo ""
echo "scp -i YOUR_KEY.pem ubuntu@${PUBLIC_IP}:${INSTALL_DIR}/clash.yaml \"%USERPROFILE%\\Downloads\\aws-clash.yaml\""
echo ""
echo "Example:"
echo "scp -i aws-clash-key.pem ubuntu@${PUBLIC_IP}:${INSTALL_DIR}/clash.yaml \"%USERPROFILE%\\Downloads\\aws-clash.yaml\""
echo ""
echo "After downloading, import this file into Clash:"
echo "%USERPROFILE%\\Downloads\\aws-clash.yaml"