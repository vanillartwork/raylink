#!/usr/bin/env bash
set -euo pipefail

DIRECT_PORT="${DIRECT_PORT:-443}"
FORWARD_PORT="${FORWARD_PORT:-8843}"

METHOD="${METHOD:-aes-256-gcm}"
NODE_NAME_DIRECT="${NODE_NAME_DIRECT:-Aliyun-HK}"
NODE_NAME_FORWARD="${NODE_NAME_FORWARD:-GCP-via-HK}"

INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-ss-relay}"
SINGBOX_DIR="/etc/sing-box"
SINGBOX_CONFIG="${SINGBOX_DIR}/config.json"
SINGBOX_BIN="/usr/local/bin/sing-box"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"

TARGET_IP="${TARGET_IP:-}"
TARGET_PORT="${TARGET_PORT:-}"
TARGET_METHOD="${TARGET_METHOD:-aes-256-gcm}"
TARGET_PASSWORD="${TARGET_PASSWORD:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root."
  echo "Example:"
  echo "sudo bash relay.sh"
  exit 1
fi

if [ -z "${TARGET_IP}" ] || [ -z "${TARGET_PORT}" ] || [ -z "${TARGET_PASSWORD}" ]; then
  echo "Missing required terminal node information."
  echo ""
  echo "Required variables:"
  echo "TARGET_IP=terminal_public_ip"
  echo "TARGET_PORT=terminal_port"
  echo "TARGET_PASSWORD=terminal_password"
  echo ""
  echo "Example:"
  echo "TARGET_IP=136.117.240.22 TARGET_PORT=10000 TARGET_PASSWORD='xxx' bash relay.sh"
  exit 1
fi

echo "=========================================="
echo " Native sing-box Relay Node Setup"
echo "=========================================="

echo "[1/9] Installing required packages..."
apt update
apt install -y curl ca-certificates openssl tar gzip

echo "[2/9] Enabling BBR..."
cat > /etc/sysctl.d/99-cloud-ss-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1 || true

echo "[3/9] Preparing directories..."
mkdir -p "${INSTALL_DIR}" "${SINGBOX_DIR}"

echo "[4/9] Detecting public IPv4..."
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

echo "[5/9] Stopping old services that may occupy ports..."
systemctl disable --now shadowsocks-libev >/dev/null 2>&1 || true

if command -v docker >/dev/null 2>&1; then
  docker rm -f ss-server >/dev/null 2>&1 || true
fi

systemctl stop sing-box >/dev/null 2>&1 || true

echo "[6/9] Installing sing-box..."

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64)
    SB_ARCH="amd64"
    ;;
  aarch64|arm64)
    SB_ARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

if ! command -v "${SINGBOX_BIN}" >/dev/null 2>&1; then
  TMP_DIR="$(mktemp -d)"
  cd "${TMP_DIR}"

  RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest)"
  DOWNLOAD_URL="$(printf '%s' "${RELEASE_JSON}" | grep -oE "https://[^\"]+linux-${SB_ARCH}\.tar\.gz" | head -n 1)"

  if [ -z "${DOWNLOAD_URL}" ]; then
    echo "Failed to find sing-box download URL."
    exit 1
  fi

  curl -fL "${DOWNLOAD_URL}" -o sing-box.tar.gz
  tar -xzf sing-box.tar.gz

  FOUND_BIN="$(find . -type f -name sing-box | head -n 1)"
  if [ -z "${FOUND_BIN}" ]; then
    echo "Failed to find sing-box binary after extraction."
    exit 1
  fi

  install -m 755 "${FOUND_BIN}" "${SINGBOX_BIN}"

  cd /
  rm -rf "${TMP_DIR}"
fi

"${SINGBOX_BIN}" version || true

echo "[7/9] Generating relay passwords..."
RELAY_DIRECT_PASSWORD="${RELAY_DIRECT_PASSWORD:-$(openssl rand -hex 16)}"
RELAY_FORWARD_PASSWORD="${RELAY_FORWARD_PASSWORD:-$(openssl rand -hex 16)}"

echo "[8/9] Writing sing-box config..."

cat > "${SINGBOX_CONFIG}" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in-direct",
      "listen": "0.0.0.0",
      "listen_port": ${DIRECT_PORT},
      "method": "${METHOD}",
      "password": "${RELAY_DIRECT_PASSWORD}"
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in-forward",
      "listen": "0.0.0.0",
      "listen_port": ${FORWARD_PORT},
      "method": "${METHOD}",
      "password": "${RELAY_FORWARD_PASSWORD}"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "shadowsocks",
      "tag": "terminal",
      "server": "${TARGET_IP}",
      "server_port": ${TARGET_PORT},
      "method": "${TARGET_METHOD}",
      "password": "${TARGET_PASSWORD}"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": [
          "ss-in-direct"
        ],
        "outbound": "direct"
      },
      {
        "inbound": [
          "ss-in-forward"
        ],
        "outbound": "terminal"
      }
    ],
    "final": "direct"
  }
}
EOF

chmod 600 "${SINGBOX_CONFIG}"

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box relay service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=${SINGBOX_BIN} run -c ${SINGBOX_CONFIG}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

"${SINGBOX_BIN}" check -c "${SINGBOX_CONFIG}"

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box

sleep 1

if ! systemctl is-active --quiet sing-box; then
  echo "sing-box failed to start."
  systemctl status sing-box --no-pager || true
  journalctl -u sing-box -n 80 --no-pager || true
  exit 1
fi

echo "[9/9] Generating Clash config and ss:// links..."

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
  - name: "${NODE_NAME_DIRECT}"
    type: ss
    server: ${PUBLIC_IP}
    port: ${DIRECT_PORT}
    cipher: ${METHOD}
    password: "${RELAY_DIRECT_PASSWORD}"
    udp: true

  - name: "${NODE_NAME_FORWARD}"
    type: ss
    server: ${PUBLIC_IP}
    port: ${FORWARD_PORT}
    cipher: ${METHOD}
    password: "${RELAY_FORWARD_PASSWORD}"
    udp: true

proxy-groups:
  - name: "GLOBAL"
    type: select
    proxies:
      - ${NODE_NAME_DIRECT}
      - ${NODE_NAME_FORWARD}
      - DIRECT

rules:
  - MATCH,GLOBAL
EOF

DIRECT_USERINFO="$(printf '%s' "${METHOD}:${RELAY_DIRECT_PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"
FORWARD_USERINFO="$(printf '%s' "${METHOD}:${RELAY_FORWARD_PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"

DIRECT_URI="ss://${DIRECT_USERINFO}@${PUBLIC_IP}:${DIRECT_PORT}#${NODE_NAME_DIRECT}"
FORWARD_URI="ss://${FORWARD_USERINFO}@${PUBLIC_IP}:${FORWARD_PORT}#${NODE_NAME_FORWARD}"

cat > "${SS_FILE}" <<EOF
Direct relay ss:// link:
${DIRECT_URI}

Forwarded terminal ss:// link:
${FORWARD_URI}
EOF

cat > "${INFO_FILE}" <<EOF
Server information:
Node role: Relay
Server type: Native sing-box

Relay public IP: ${PUBLIC_IP}

Direct node:
Name: ${NODE_NAME_DIRECT}
Server: ${PUBLIC_IP}
Port: ${DIRECT_PORT}
Cipher: ${METHOD}
Password: ${RELAY_DIRECT_PASSWORD}

Forward node:
Name: ${NODE_NAME_FORWARD}
Server: ${PUBLIC_IP}
Port: ${FORWARD_PORT}
Cipher: ${METHOD}
Password: ${RELAY_FORWARD_PASSWORD}

Terminal target:
Target IP: ${TARGET_IP}
Target Port: ${TARGET_PORT}
Target Cipher: ${TARGET_METHOD}
Target Password: ${TARGET_PASSWORD}

Files:
${INFO_FILE}
${CLASH_FILE}
${SS_FILE}
${SINGBOX_CONFIG}
EOF

chmod 600 "${INFO_FILE}" "${SINGBOX_CONFIG}"
chmod 644 "${CLASH_FILE}" "${SS_FILE}"

echo ""
echo "=========================================="
echo "Setup complete"
echo "=========================================="
cat "${INFO_FILE}"

echo ""
echo "sing-box status:"
systemctl status sing-box --no-pager || true

echo ""
echo "Listening ports:"
ss -tulnp | grep -E ":(${DIRECT_PORT}|${FORWARD_PORT})" || true

echo ""
echo "Important:"
echo "Make sure your relay cloud firewall/security group allows:"
echo "TCP ${DIRECT_PORT}"
echo "UDP ${DIRECT_PORT}"
echo "TCP ${FORWARD_PORT}"
echo "UDP ${FORWARD_PORT}"

echo ""
echo "Direct relay ss:// link:"
echo "${DIRECT_URI}"

echo ""
echo "Forwarded terminal ss:// link:"
echo "${FORWARD_URI}"
