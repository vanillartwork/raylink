#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-443}"
METHOD="${METHOD:-aes-256-gcm}"
INSTALL_DIR="${INSTALL_DIR:-/opt/clash-ss}"
SERVICE_NAME="${SERVICE_NAME:-shadowsocks-libev}"
CONFIG_DIR="${CONFIG_DIR:-/etc/shadowsocks-libev}"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"
NODE_NAME="${NODE_NAME:-China-SS}"

echo "======================================"
echo " Shadowsocks + Clash Setup"
echo " Installation method: apt"
echo " Port: ${PORT}"
echo " Method: ${METHOD}"
echo " Service: ${SERVICE_NAME}"
echo " Install directory: ${INSTALL_DIR}"
echo "======================================"

if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script with sudo:"
    echo "sudo bash clash_ss_apt.sh"
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "Error: this script is designed for Ubuntu/Debian systems using apt."
    exit 1
fi

mkdir -p "${INSTALL_DIR}"
mkdir -p "${CONFIG_DIR}"

echo "[1/9] Updating apt package list..."
apt update -y

echo "[2/9] Installing required packages..."
apt install -y curl ca-certificates gnupg openssl shadowsocks-libev

echo "[3/9] Generating Shadowsocks password..."
PASSWORD="$(openssl rand -hex 16)"

echo "[4/9] Detecting public IPv4..."

PUBLIC_IP="$(
    curl -4 -s -m 5 https://api.ipify.org ||
    curl -4 -s -m 5 https://ifconfig.me ||
    curl -4 -s -m 5 http://ip.sb ||
    curl -4 -s -m 5 http://4.ipw.cn ||
    true
)"

if [ -z "${PUBLIC_IP}" ]; then
    PUBLIC_IP="YOUR_PUBLIC_IP"
    echo "Warning: failed to detect public IPv4 automatically."
    echo "Please replace YOUR_PUBLIC_IP in the generated client config manually."
fi

echo "[5/9] Generating Shadowsocks server configuration..."

cat > "${CONFIG_FILE}" <<EOF
{
    "server": "0.0.0.0",
    "server_port": ${PORT},
    "password": "${PASSWORD}",
    "timeout": 300,
    "method": "${METHOD}",
    "mode": "tcp_and_udp",
    "fast_open": false,
    "nameserver": "1.1.1.1"
}
EOF

chmod 600 "${CONFIG_FILE}"

echo "[6/9] Enabling and restarting Shadowsocks service..."

systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
systemctl restart "${SERVICE_NAME}"

echo "[7/9] Generating Clash configuration..."

cat > "${INFO_FILE}" <<EOF
Server type: Shadowsocks
Installation method: apt
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Cipher: ${METHOD}
Password: ${PASSWORD}
Service: ${SERVICE_NAME}
Server config: ${CONFIG_FILE}
EOF

cat > "${CLASH_FILE}" <<EOF
mixed-port: 7890
allow-lan: false
mode: global
log-level: info

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

echo "[8/9] Generating Shadowsocks ss:// link for mobile clients..."

SS_USERINFO="$(printf '%s' "${METHOD}:${PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"
SS_URI="ss://${SS_USERINFO}@${PUBLIC_IP}:${PORT}#${NODE_NAME}"

cat > "${SS_FILE}" <<EOF
${SS_URI}
EOF

cat >> "${INFO_FILE}" <<EOF

Mobile ss:// link:
${SS_URI}
EOF

chmod 644 "${CLASH_FILE}" "${SS_FILE}"
chmod 600 "${INFO_FILE}"

echo "[9/9] Checking service status..."

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    SERVICE_STATUS="active"
else
    SERVICE_STATUS="inactive"
fi

echo ""
echo "======================================"
echo " Setup complete"
echo "======================================"
echo ""

echo "Server information:"
cat "${INFO_FILE}"

echo ""
echo "Clash config:"
echo "--------------------------------------"
cat "${CLASH_FILE}"
echo "--------------------------------------"

echo ""
echo "Service status:"
echo "${SERVICE_NAME}: ${SERVICE_STATUS}"

echo ""
echo "Listening ports:"
ss -tulnp | grep ":${PORT}" || true

echo ""
echo "Files saved on server:"
echo "${INFO_FILE}"
echo "${CLASH_FILE}"
echo "${SS_FILE}"
echo "${CONFIG_FILE}"

echo ""
echo "Important:"
echo "Make sure your cloud firewall/security group allows:"
echo "TCP ${PORT} from your client IP or 0.0.0.0/0"
echo "UDP ${PORT} from your client IP or 0.0.0.0/0"
echo ""
echo "For SSH, keep port 22 limited to your own IP."

echo ""
echo "Useful commands:"
echo "View service status:"
echo "sudo systemctl status ${SERVICE_NAME}"
echo ""
echo "View logs:"
echo "sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "Restart service:"
echo "sudo systemctl restart ${SERVICE_NAME}"

echo ""
echo "Mobile ss:// link:"
echo "${SS_URI}"