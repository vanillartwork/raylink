#!/usr/bin/env bash
set -euo pipefail

DIRECT_PORT="${DIRECT_PORT:-443}"
FORWARD_PORT="${FORWARD_PORT:-8843}"

METHOD="${METHOD:-chacha20-ietf-poly1305}"
NODE_NAME_DIRECT="${NODE_NAME_DIRECT:-Relay-Direct}"
NODE_NAME_FORWARD="${NODE_NAME_FORWARD:-Terminal-via-Relay}"

INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-ss-relay}"
SINGBOX_DIR="/etc/sing-box"
SINGBOX_CONFIG="${SINGBOX_DIR}/config.json"
SINGBOX_BIN="/usr/local/bin/sing-box"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"
PASSWORD_FILE="${INSTALL_DIR}/relay-passwords.env"

# Legacy NAT cleanup. Set CLEAN_LEGACY_NAT=false to skip.
CLEAN_LEGACY_NAT="${CLEAN_LEGACY_NAT:-true}"

# Relay entry passwords.
# - Provide RELAY_DIRECT_PASSWORD / RELAY_FORWARD_PASSWORD to pin them explicitly.
# - Or leave them empty and the script will reuse ${PASSWORD_FILE} on later runs.
# - Set RESET_RELAY_PASSWORDS=true to generate new relay entry passwords.
RELAY_DIRECT_PASSWORD="${RELAY_DIRECT_PASSWORD:-}"
RELAY_FORWARD_PASSWORD="${RELAY_FORWARD_PASSWORD:-}"
REUSE_RELAY_PASSWORDS="${REUSE_RELAY_PASSWORDS:-true}"
RESET_RELAY_PASSWORDS="${RESET_RELAY_PASSWORDS:-false}"

TARGET_IP="${TARGET_IP:-}"
TARGET_PORT="${TARGET_PORT:-}"
TARGET_METHOD="${TARGET_METHOD:-chacha20-ietf-poly1305}"
TARGET_PASSWORD="${TARGET_PASSWORD:-}"

valid_ipv4() {
  printf '%s' "${1:-}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

detect_public_ipv4() {
  if [ -n "${PUBLIC_IP:-}" ]; then
    printf '%s\n' "${PUBLIC_IP}"
    return 0
  fi

  local url ip
  for url in \
    "https://api.ipify.org" \
    "https://ipv4.icanhazip.com" \
    "https://checkip.amazonaws.com" \
    "https://ident.me" \
    "https://ipinfo.io/ip" \
    "https://ifconfig.me" \
    "http://ip.sb" \
    "http://4.ipw.cn"; do
    ip="$(curl -4 -fsS -m 6 "${url}" 2>/dev/null | tr -d ' \r\n\t' | head -c 64 || true)"
    if valid_ipv4 "${ip}"; then
      printf '%s\n' "${ip}"
      return 0
    fi
  done

  return 1
}

stop_old_shadowsocks_services() {
  for svc in shadowsocks-libev.service shadowsocks-libev-server@config.service; do
    systemctl disable --now "${svc}" >/dev/null 2>&1 || true
  done
}

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

cleanup_legacy_nat_rules() {
  if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables not found, skip legacy NAT cleanup."
    return 0
  fi

  echo "Cleaning legacy iptables NAT/DNAT rules for relay ports..."
  echo "Before cleanup:"
  iptables -t nat -S 2>/dev/null | grep -E "(${DIRECT_PORT}|${FORWARD_PORT}|SS_RELAY|DNAT)" || true

  # Remove PREROUTING DNAT rules that capture the ports this script needs.
  # This fixes old manual relay rules like: --dport 8843 -j DNAT --to-destination x.x.x.x:8388
  for port in "${DIRECT_PORT}" "${FORWARD_PORT}"; do
    for proto in tcp udp; do
      while read -r rule; do
        [ -z "${rule}" ] && continue
        delete_rule="${rule/-A /-D }"
        # shellcheck disable=SC2086
        iptables -t nat ${delete_rule} 2>/dev/null || true
      done < <(iptables -t nat -S PREROUTING 2>/dev/null | grep -E -- "-p ${proto} .*--dport ${port} .* -j DNAT" || true)
    done
  done

  # Remove old custom chains created by previous relay experiments.
  for hook in PREROUTING OUTPUT POSTROUTING; do
    while read -r rule; do
      [ -z "${rule}" ] && continue
      delete_rule="${rule/-A /-D }"
      # shellcheck disable=SC2086
      iptables -t nat ${delete_rule} 2>/dev/null || true
    done < <(iptables -t nat -S "${hook}" 2>/dev/null | grep -E -- " -j SS_RELAY" || true)
  done

  while read -r chain; do
    [ -z "${chain}" ] && continue
    iptables -t nat -F "${chain}" 2>/dev/null || true
    iptables -t nat -X "${chain}" 2>/dev/null || true
  done < <(iptables -t nat -S 2>/dev/null | awk '/^-N SS_RELAY/ {print $2}')

  echo "After cleanup:"
  iptables -t nat -S 2>/dev/null | grep -E "(${DIRECT_PORT}|${FORWARD_PORT}|SS_RELAY|DNAT)" || true
}

load_or_generate_relay_passwords() {
  if [ "${RESET_RELAY_PASSWORDS}" = "true" ]; then
    rm -f "${PASSWORD_FILE}"
  fi

  if [ "${REUSE_RELAY_PASSWORDS}" = "true" ] && [ -f "${PASSWORD_FILE}" ]; then
    # This file is created by this script and chmod 600.
    # shellcheck disable=SC1090
    source "${PASSWORD_FILE}"
  fi

  if [ -z "${RELAY_DIRECT_PASSWORD}" ]; then
    RELAY_DIRECT_PASSWORD="$(openssl rand -hex 16)"
  fi

  if [ -z "${RELAY_FORWARD_PASSWORD}" ]; then
    RELAY_FORWARD_PASSWORD="$(openssl rand -hex 16)"
  fi

  {
    printf 'RELAY_DIRECT_PASSWORD=%q\n' "${RELAY_DIRECT_PASSWORD}"
    printf 'RELAY_FORWARD_PASSWORD=%q\n' "${RELAY_FORWARD_PASSWORD}"
  } > "${PASSWORD_FILE}"
  chmod 600 "${PASSWORD_FILE}"
}

echo "=========================================="
echo " Native sing-box Generic Relay Setup"
echo "=========================================="

echo "[1/10] Installing required packages..."
apt update
apt install -y curl ca-certificates openssl tar gzip

echo "[2/10] Enabling BBR..."
cat > /etc/sysctl.d/99-cloud-ss-bbr.conf <<SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true

echo "[3/10] Preparing directories..."
mkdir -p "${INSTALL_DIR}" "${SINGBOX_DIR}"

echo "[4/10] Detecting public IPv4..."
PUBLIC_IP="$(detect_public_ipv4 || true)"

if [ -z "${PUBLIC_IP}" ]; then
  echo "Failed to detect public IPv4."
  echo "You can rerun with PUBLIC_IP=x.x.x.x"
  exit 1
fi

echo "Public IPv4: ${PUBLIC_IP}"

echo "[5/10] Cleaning legacy NAT/DNAT rules..."
if [ "${CLEAN_LEGACY_NAT}" = "true" ]; then
  cleanup_legacy_nat_rules
else
  echo "Skip legacy NAT cleanup because CLEAN_LEGACY_NAT=false"
fi

echo "[6/10] Stopping old services that may occupy ports..."
stop_old_shadowsocks_services

if command -v docker >/dev/null 2>&1; then
  docker rm -f ss-server >/dev/null 2>&1 || true
fi

systemctl stop sing-box >/dev/null 2>&1 || true

echo "[7/10] Installing sing-box..."

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

echo "[8/10] Loading or generating relay entry passwords..."
load_or_generate_relay_passwords

echo "[9/10] Writing sing-box config..."

cat > "${SINGBOX_CONFIG}" <<CONFIG_EOF
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
CONFIG_EOF

chmod 600 "${SINGBOX_CONFIG}"

cat > /etc/systemd/system/sing-box.service <<SERVICE_EOF
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
SERVICE_EOF

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

echo "[10/10] Generating Clash config and ss:// links..."

cat > "${CLASH_FILE}" <<CLASH_EOF
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
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'localhost.ptlogin2.qq.com'
    - '*.msftconnecttest.com'
    - '*.msftncsi.com'
    - 'time.*.com'
    - 'time.*.gov'
    - 'time.*.edu.cn'
    - 'time.*.apple.com'
    - 'ntp.*.com'
    - 'ntp.*.com.cn'
    - '*.pool.ntp.org'
    - '+.stun.*.*'
    - '+.stun.*.*.*'
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
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
CLASH_EOF

DIRECT_USERINFO="$(printf '%s' "${METHOD}:${RELAY_DIRECT_PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"
FORWARD_USERINFO="$(printf '%s' "${METHOD}:${RELAY_FORWARD_PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"

DIRECT_URI="ss://${DIRECT_USERINFO}@${PUBLIC_IP}:${DIRECT_PORT}#${NODE_NAME_DIRECT}"
FORWARD_URI="ss://${FORWARD_USERINFO}@${PUBLIC_IP}:${FORWARD_PORT}#${NODE_NAME_FORWARD}"

cat > "${SS_FILE}" <<SS_EOF
Direct relay ss:// link:
${DIRECT_URI}

Forwarded terminal ss:// link:
${FORWARD_URI}
SS_EOF

cat > "${INFO_FILE}" <<INFO_EOF
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
${PASSWORD_FILE}
${SINGBOX_CONFIG}
INFO_EOF

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
echo "Relay entry passwords are saved in: ${PASSWORD_FILE}"
echo "To keep client configs unchanged when changing terminal node, keep this file or pass:"
echo "RELAY_DIRECT_PASSWORD='...' RELAY_FORWARD_PASSWORD='...'"
echo ""
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
