#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-10000}"
METHOD="${METHOD:-aes-256-gcm}"
NODE_NAME="${NODE_NAME:-Terminal-SS}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-ss-clash}"
CONFIG_DIR="/etc/shadowsocks-libev"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root, for example:"
  echo "sudo env PORT=${PORT} NODE_NAME=${NODE_NAME} bash terminal.sh"
  exit 1
fi

echo "=========================================="
echo " Native Shadowsocks Terminal Node Setup"
echo "=========================================="

echo "[1/8] Installing required packages..."
apt update
apt install -y curl ca-certificates openssl shadowsocks-libev

echo "[2/8] Enabling BBR..."
cat > /etc/sysctl.d/99-cloud-ss-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1 || true

echo "[3/8] Preparing directories..."
mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}"

echo "[4/8] Detecting public IPv4..."
PUBLIC_IP="${PUBLIC_IP:-}"
if [ -z "${PUBLIC_IP}" ]; then
  PUBLIC_IP="$(
    curl -4 -s -m 5 https://api.ipify.org ||
    curl -4 -s -m 5 https://ifconfig.me ||
    curl -4 -s -m 5 http://ip.sb ||
    curl -4 -s -m 5 http://4.ipw.cn ||
    true
  )"
fi

if [ -z "${PUBLIC_IP}" ]; then
  echo "Failed to detect public IPv4."
  echo "You can rerun with PUBLIC_IP=x.x.x.x"
  exit 1
fi

echo "[5/8] Generating password..."
PASSWORD="${PASSWORD:-$(openssl rand -hex 16)}"

echo "[6/8] Writing Shadowsocks config..."
cat > "${CONFIG_FILE}" <<EOF
{
  "server": "0.0.0.0",
  "server_port": ${PORT},
  "password": "${PASSWORD}",
  "timeout": 300,
  "method": "${METHOD}",
  "mode": "tcp_and_udp",
  "fast_open": false,
  "reuse_port": true,
  "no_delay": true,
  "nameserver": "1.1.1.1"
}
EOF

chmod 644 "${CONFIG_FILE}"

echo "[7/8] Starting Shadowsocks service..."
systemctl enable shadowsocks-libev >/dev/null 2>&1 || true
systemctl restart shadowsocks-libev

sleep 1

if ! systemctl is-active --quiet shadowsocks-libev; then
  echo "Shadowsocks failed to start."
  systemctl status shadowsocks-libev --no-pager || true
  exit 1
fi

echo "[8/8] Generating Clash config and ss:// link..."

cat > "${CLASH_FILE}" <<EOF
mixed-port: 7890
allow-lan: false
mode: global
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://dns.google/dns-query
  fallback-filter:
    geoip: true
    geoip-code: CN

proxies:
  - name: "${NODE_NAME}"
    type: ss
    server: ${PUBLIC_IP}
    port: ${PORT}
    cipher: ${METHOD}
    password: "${PASSWORD}"
    udp: true

proxy-groups:
  - name: "GLOBAL"
    type: select
    proxies:
      - ${NODE_NAME}
      - DIRECT

rules:
  - MATCH,GLOBAL
EOF

SS_USERINFO="$(printf '%s' "${METHOD}:${PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"
SS_URI="ss://${SS_USERINFO}@${PUBLIC_IP}:${PORT}#${NODE_NAME}"

cat > "${SS_FILE}" <<EOF
${SS_URI}
EOF

cat > "${INFO_FILE}" <<EOF
Server information:
Node role: Terminal
Server type: Native Shadowsocks
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Cipher: ${METHOD}
Password: ${PASSWORD}
Node name: ${NODE_NAME}

Mobile ss:// link:
${SS_URI}

Files:
${INFO_FILE}
${CLASH_FILE}
${SS_FILE}
${CONFIG_FILE}
EOF

chmod 600 "${INFO_FILE}"
chmod 644 "${CLASH_FILE}" "${SS_FILE}"

echo ""
echo "=========================================="
echo "Setup complete"
echo "=========================================="
cat "${INFO_FILE}"

echo ""
echo "Service status:"
systemctl status shadowsocks-libev --no-pager || true

echo ""
echo "Listening ports:"
ss -tulnp | grep "${PORT}" || true

echo ""
echo "Important: allow TCP/UDP ${PORT} in your cloud firewall/security group."

echo ""
echo "Mobile ss:// link:"
echo "${SS_URI}"
