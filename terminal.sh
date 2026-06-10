#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-10000}"
METHOD="${METHOD:-chacha20-ietf-poly1305}"
NODE_NAME="${NODE_NAME:-Terminal-Direct}"

INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-ss-terminal}"
CONFIG_DIR="/etc/shadowsocks-libev"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"
PASSWORD_ENV_FILE="${INSTALL_DIR}/terminal-password.env"

# Optional Clash subscription hosting. Disabled by default.
ENABLE_SUBSCRIPTION="${ENABLE_SUBSCRIPTION:-false}"
SUB_PORT="${SUB_PORT:-8080}"
SUB_TOKEN="${SUB_TOKEN:-}"
SUB_ROOT="${INSTALL_DIR}/public"
SUB_ENV_FILE="${INSTALL_DIR}/subscription.env"
NGINX_SITE="/etc/nginx/sites-available/cloud-ss-terminal-subscription"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/cloud-ss-terminal-subscription"
RESET_TERMINAL_PASSWORD="${RESET_TERMINAL_PASSWORD:-false}"
RESET_SUB_TOKEN="${RESET_SUB_TOKEN:-false}"

SS_SERVICE=""

is_true() {
  case "${1:-}" in
    true|TRUE|yes|YES|1|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

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

detect_shadowsocks_service() {
  # Ubuntu often has shadowsocks-libev.service.
  # Debian variants may use the template service shadowsocks-libev-server@config.service.
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx 'shadowsocks-libev.service'; then
    SS_SERVICE='shadowsocks-libev.service'
    return 0
  fi

  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx 'shadowsocks-libev-server@.service'; then
    SS_SERVICE='shadowsocks-libev-server@config.service'
    return 0
  fi

  if systemctl cat shadowsocks-libev.service >/dev/null 2>&1; then
    SS_SERVICE='shadowsocks-libev.service'
    return 0
  fi

  if systemctl cat shadowsocks-libev-server@.service >/dev/null 2>&1; then
    SS_SERVICE='shadowsocks-libev-server@config.service'
    return 0
  fi

  echo "Could not find a compatible shadowsocks-libev systemd unit."
  echo "Expected one of: shadowsocks-libev.service or shadowsocks-libev-server@.service"
  return 1
}

restart_shadowsocks() {
  detect_shadowsocks_service
  echo "Using Shadowsocks service: ${SS_SERVICE}"
  systemctl enable "${SS_SERVICE}" >/dev/null 2>&1 || true
  systemctl restart "${SS_SERVICE}"
}

show_shadowsocks_status() {
  if [ -n "${SS_SERVICE}" ]; then
    systemctl status "${SS_SERVICE}" --no-pager || true
  else
    systemctl status shadowsocks-libev --no-pager || true
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root, for example:"
  echo "sudo env PORT=${PORT} NODE_NAME=${NODE_NAME} bash terminal.sh"
  exit 1
fi

echo "=========================================="
echo " Native Shadowsocks Generic Terminal Setup"
echo "=========================================="

echo "[1/9] Installing required packages..."
apt update
apt install -y curl ca-certificates openssl shadowsocks-libev

if is_true "${ENABLE_SUBSCRIPTION}"; then
  apt install -y nginx
fi

echo "[2/9] Enabling BBR..."
cat > /etc/sysctl.d/99-cloud-ss-bbr.conf <<SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true

echo "[3/9] Preparing directories..."
mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}"

echo "[4/9] Detecting public IPv4..."
PUBLIC_IP="$(detect_public_ipv4 || true)"

if [ -z "${PUBLIC_IP}" ]; then
  echo "Failed to detect public IPv4."
  echo "You can rerun with PUBLIC_IP=x.x.x.x"
  exit 1
fi

echo "Public IPv4: ${PUBLIC_IP}"

echo "[5/9] Preparing terminal password..."
if [ -z "${PASSWORD:-}" ] && ! is_true "${RESET_TERMINAL_PASSWORD}" && [ -f "${PASSWORD_ENV_FILE}" ]; then
  # shellcheck disable=SC1090
  . "${PASSWORD_ENV_FILE}"
fi

PASSWORD="${PASSWORD:-$(openssl rand -hex 16)}"
cat > "${PASSWORD_ENV_FILE}" <<PASSWORD_EOF
PASSWORD='${PASSWORD}'
PASSWORD_EOF
chmod 600 "${PASSWORD_ENV_FILE}"

echo "[6/9] Writing Shadowsocks config..."
cat > "${CONFIG_FILE}" <<CONFIG_EOF
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
CONFIG_EOF

chmod 644 "${CONFIG_FILE}"

echo "[7/9] Starting Shadowsocks service..."
restart_shadowsocks

sleep 1

if ! systemctl is-active --quiet "${SS_SERVICE}"; then
  echo "Shadowsocks failed to start."
  show_shadowsocks_status
  exit 1
fi

echo "[8/9] Generating Clash config and ss:// link..."

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
CLASH_EOF

SS_USERINFO="$(printf '%s' "${METHOD}:${PASSWORD}" | base64 | tr -d '\n' | tr '+/' '-_' | sed 's/=*$//')"
SS_URI="ss://${SS_USERINFO}@${PUBLIC_IP}:${PORT}#${NODE_NAME}"

cat > "${SS_FILE}" <<SS_EOF
${SS_URI}
SS_EOF

SUBSCRIPTION_URL=""

echo "[9/9] Configuring optional subscription hosting..."
if is_true "${ENABLE_SUBSCRIPTION}"; then
  if [ -z "${SUB_TOKEN}" ] && ! is_true "${RESET_SUB_TOKEN}" && [ -f "${SUB_ENV_FILE}" ]; then
    # shellcheck disable=SC1090
    . "${SUB_ENV_FILE}"
  fi

  SUB_TOKEN="${SUB_TOKEN:-$(openssl rand -hex 24)}"
  SUB_PATH="sub/${SUB_TOKEN}/clash.yaml"
  SUB_DIR="${SUB_ROOT}/sub/${SUB_TOKEN}"
  SUB_FILE="${SUB_DIR}/clash.yaml"
  SUBSCRIPTION_URL="http://${PUBLIC_IP}:${SUB_PORT}/${SUB_PATH}"

  mkdir -p "${SUB_DIR}"
  cp "${CLASH_FILE}" "${SUB_FILE}"
  chmod 755 "${SUB_ROOT}" "${SUB_ROOT}/sub" "${SUB_DIR}"
  chmod 644 "${SUB_FILE}"

  cat > "${SUB_ENV_FILE}" <<SUB_EOF
SUB_TOKEN='${SUB_TOKEN}'
SUB_PORT='${SUB_PORT}'
SUBSCRIPTION_URL='${SUBSCRIPTION_URL}'
SUB_EOF
  chmod 600 "${SUB_ENV_FILE}"

  cat > "${NGINX_SITE}" <<NGINX_EOF
server {
    listen ${SUB_PORT};
    server_name _;

    root ${SUB_ROOT};
    autoindex off;

    location / {
        try_files \$uri =404;
        default_type text/plain;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX_EOF

  ln -sf "${NGINX_SITE}" "${NGINX_SITE_LINK}"
  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx
fi

cat > "${INFO_FILE}" <<INFO_EOF
Server information:
Node role: Terminal
Server type: Native Shadowsocks
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Cipher: ${METHOD}
Password: ${PASSWORD}
Node name: ${NODE_NAME}
Systemd service: ${SS_SERVICE}

Mobile ss:// link:
${SS_URI}

Files:
${INFO_FILE}
${CLASH_FILE}
${SS_FILE}
${CONFIG_FILE}
${PASSWORD_ENV_FILE}
INFO_EOF

if is_true "${ENABLE_SUBSCRIPTION}"; then
  cat >> "${INFO_FILE}" <<INFO_SUB_EOF

Subscription:
Enabled: true
URL: ${SUBSCRIPTION_URL}
Port: ${SUB_PORT}
Token: ${SUB_TOKEN}
Public file: ${SUB_ROOT}/sub/${SUB_TOKEN}/clash.yaml
Nginx config: ${NGINX_SITE}
INFO_SUB_EOF
else
  cat >> "${INFO_FILE}" <<INFO_SUB_EOF

Subscription:
Enabled: false
To enable: ENABLE_SUBSCRIPTION=true bash terminal.sh
INFO_SUB_EOF
fi

chmod 600 "${INFO_FILE}" "${PASSWORD_ENV_FILE}"
chmod 644 "${CLASH_FILE}" "${SS_FILE}"

echo ""
echo "=========================================="
echo "Setup complete"
echo "=========================================="
cat "${INFO_FILE}"

echo ""
echo "Service status:"
show_shadowsocks_status

if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo ""
  echo "Nginx status:"
  systemctl status nginx --no-pager || true
fi

echo ""
echo "Listening ports:"
ss -tulnp | grep -E ":(${PORT}|${SUB_PORT})" || true

echo ""
echo "Important: allow TCP/UDP ${PORT} in your cloud firewall/security group."
if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo "Important: allow TCP ${SUB_PORT} if you want to access the subscription URL from outside."
  echo "Do not publish the subscription URL publicly; it contains your node password."
fi

echo ""
echo "Mobile ss:// link:"
echo "${SS_URI}"

if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo ""
  echo "Clash subscription URL:"
  echo "${SUBSCRIPTION_URL}"
fi
