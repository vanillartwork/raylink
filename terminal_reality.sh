#!/usr/bin/env bash
set -euo pipefail

# Generic Xray VLESS Reality terminal node with optional HTTP Clash subscription hosting.
# Tested syntax with: bash -n

PORT="${PORT:-10000}"
NODE_NAME="${NODE_NAME:-Terminal-Reality}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-xray-terminal}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
XRAY_CONFIG="${XRAY_CONFIG:-${XRAY_CONFIG_DIR}/config.json}"
XRAY_SHARE_DIR="${XRAY_SHARE_DIR:-/usr/local/share/xray}"
XRAY_SERVICE="xray.service"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
VLESS_FILE="${INSTALL_DIR}/vless-uri.txt"
REALITY_ENV_FILE="${INSTALL_DIR}/reality.env"

# Reality settings. REALITY_SERVER_NAME should match REALITY_DEST host in most cases.
REALITY_DEST="${REALITY_DEST:-www.microsoft.com:443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.microsoft.com}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
FLOW="${FLOW:-xtls-rprx-vision}"

# Optional Clash subscription hosting. Disabled by default.
ENABLE_SUBSCRIPTION="${ENABLE_SUBSCRIPTION:-false}"
SUB_PORT="${SUB_PORT:-8080}"
SUB_TOKEN="${SUB_TOKEN:-}"
SUB_ROOT="${INSTALL_DIR}/public"
SUB_ENV_FILE="${INSTALL_DIR}/subscription.env"
NGINX_SITE="/etc/nginx/sites-available/cloud-xray-terminal-subscription"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/cloud-xray-terminal-subscription"
RESET_SUB_TOKEN="${RESET_SUB_TOKEN:-false}"

# Credential/key reuse. Leave as default to keep client configs stable across reruns.
RESET_REALITY_CREDENTIALS="${RESET_REALITY_CREDENTIALS:-false}"
UUID="${UUID:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
SHORT_ID="${SHORT_ID:-}"

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

install_xray() {
  if [ -x "${XRAY_BIN}" ]; then
    "${XRAY_BIN}" version || true
    return 0
  fi

  echo "Installing Xray-core from GitHub latest release..."

  local arch xray_arch tmp_dir release_json download_url found_bin
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64)
      xray_arch="64"
      ;;
    aarch64|arm64)
      xray_arch="arm64-v8a"
      ;;
    armv7l|armv7)
      xray_arch="arm32-v7a"
      ;;
    *)
      echo "Unsupported architecture: ${arch}"
      exit 1
      ;;
  esac

  tmp_dir="$(mktemp -d)"
  cd "${tmp_dir}"

  release_json="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest)"
  download_url="$(printf '%s' "${release_json}" | grep -oE "https://[^\"]+Xray-linux-${xray_arch}\.zip" | head -n 1)"

  if [ -z "${download_url}" ]; then
    echo "Failed to find Xray download URL for linux-${xray_arch}."
    exit 1
  fi

  curl -fL "${download_url}" -o xray.zip
  unzip -o xray.zip >/dev/null

  found_bin="$(find . -maxdepth 2 -type f -name xray | head -n 1)"
  if [ -z "${found_bin}" ]; then
    echo "Failed to find xray binary after extraction."
    exit 1
  fi

  install -m 755 "${found_bin}" "${XRAY_BIN}"

  mkdir -p "${XRAY_SHARE_DIR}"
  if [ -f geoip.dat ]; then
    install -m 644 geoip.dat "${XRAY_SHARE_DIR}/geoip.dat"
  fi
  if [ -f geosite.dat ]; then
    install -m 644 geosite.dat "${XRAY_SHARE_DIR}/geosite.dat"
  fi

  cd /
  rm -rf "${tmp_dir}"

  "${XRAY_BIN}" version || true
}

load_or_generate_reality_credentials() {
  if is_true "${RESET_REALITY_CREDENTIALS}"; then
    rm -f "${REALITY_ENV_FILE}"
  fi

  if [ -f "${REALITY_ENV_FILE}" ]; then
    # This file is created by this script and chmod 600.
    # shellcheck disable=SC1090
    . "${REALITY_ENV_FILE}"
  fi

  if [ -z "${UUID}" ]; then
    UUID="$(${XRAY_BIN} uuid | tr -d ' \r\n\t')"
  fi

  if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ]; then
    local keypair
    keypair="$(${XRAY_BIN} x25519)"
    PRIVATE_KEY="$(printf '%s\n' "${keypair}" | awk -F': ' '/Private key/ {print $2}' | tr -d ' \r\n\t')"
    PUBLIC_KEY="$(printf '%s\n' "${keypair}" | awk -F': ' '/Public key/ {print $2}' | tr -d ' \r\n\t')"
  fi

  if [ -z "${SHORT_ID}" ]; then
    SHORT_ID="$(openssl rand -hex 8)"
  fi

  if [ -z "${UUID}" ] || [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ] || [ -z "${SHORT_ID}" ]; then
    echo "Failed to generate Reality credentials."
    exit 1
  fi

  {
    printf 'UUID=%q\n' "${UUID}"
    printf 'PRIVATE_KEY=%q\n' "${PRIVATE_KEY}"
    printf 'PUBLIC_KEY=%q\n' "${PUBLIC_KEY}"
    printf 'SHORT_ID=%q\n' "${SHORT_ID}"
  } > "${REALITY_ENV_FILE}"
  chmod 600 "${REALITY_ENV_FILE}"
}

write_xray_service() {
  cat > /etc/systemd/system/${XRAY_SERVICE} <<SERVICE_EOF
[Unit]
Description=Xray VLESS Reality terminal service
Documentation=https://xtls.github.io/
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
User=root
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SERVICE_EOF
}

write_xray_config() {
  mkdir -p "${XRAY_CONFIG_DIR}"

  cat > "${XRAY_CONFIG}" <<CONFIG_EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "${FLOW}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
CONFIG_EOF

  chmod 600 "${XRAY_CONFIG}"
}

write_clash_config() {
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
    type: vless
    server: ${PUBLIC_IP}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    udp: true
    tls: true
    servername: ${REALITY_SERVER_NAME}
    flow: ${FLOW}
    client-fingerprint: ${CLIENT_FINGERPRINT}
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}

proxy-groups:
  - name: "GLOBAL"
    type: select
    proxies:
      - ${NODE_NAME}
      - DIRECT

rules:
  - MATCH,GLOBAL
CLASH_EOF

  chmod 644 "${CLASH_FILE}"
}

configure_subscription() {
  SUBSCRIPTION_URL=""

  if ! is_true "${ENABLE_SUBSCRIPTION}"; then
    return 0
  fi

  if [ "${SUB_PORT}" = "${PORT}" ]; then
    echo "SUB_PORT must be different from PORT. Current value: ${SUB_PORT}"
    exit 1
  fi

  apt install -y nginx

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
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root, for example:"
  echo "sudo env PORT=${PORT} NODE_NAME=${NODE_NAME} bash terminal_reality.sh"
  exit 1
fi

if is_true "${ENABLE_SUBSCRIPTION}" && [ "${SUB_PORT}" = "${PORT}" ]; then
  echo "SUB_PORT must be different from PORT. Current value: ${SUB_PORT}"
  exit 1
fi

echo "=========================================="
echo " Xray VLESS Reality Generic Terminal Setup"
echo "=========================================="

echo "[1/10] Installing required packages..."
apt update
apt install -y curl ca-certificates openssl unzip

echo "[2/10] Enabling BBR..."
cat > /etc/sysctl.d/99-cloud-xray-bbr.conf <<SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true

echo "[3/10] Preparing directories..."
mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"

echo "[4/10] Detecting public IPv4..."
PUBLIC_IP="$(detect_public_ipv4 || true)"
if [ -z "${PUBLIC_IP}" ]; then
  echo "Failed to detect public IPv4. You can rerun with PUBLIC_IP=x.x.x.x"
  exit 1
fi
echo "Public IPv4: ${PUBLIC_IP}"

echo "[5/10] Stopping old services that may occupy the terminal port..."
systemctl disable --now shadowsocks-libev >/dev/null 2>&1 || true
systemctl disable --now shadowsocks-libev-server@config.service >/dev/null 2>&1 || true
systemctl stop "${XRAY_SERVICE}" >/dev/null 2>&1 || true

echo "[6/10] Installing Xray-core..."
install_xray

echo "[7/10] Loading or generating VLESS/Reality credentials..."
load_or_generate_reality_credentials

echo "[8/10] Writing Xray config and systemd service..."
write_xray_config
write_xray_service

"${XRAY_BIN}" run -test -config "${XRAY_CONFIG}"

systemctl daemon-reload
systemctl enable "${XRAY_SERVICE}" >/dev/null 2>&1
systemctl restart "${XRAY_SERVICE}"

sleep 1

if ! systemctl is-active --quiet "${XRAY_SERVICE}"; then
  echo "Xray failed to start."
  systemctl status "${XRAY_SERVICE}" --no-pager || true
  journalctl -u "${XRAY_SERVICE}" -n 80 --no-pager || true
  exit 1
fi

echo "[9/10] Generating Mihomo/Clash config and vless:// link..."
write_clash_config

VLESS_URI="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=none&security=reality&sni=${REALITY_SERVER_NAME}&fp=${CLIENT_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=${FLOW}#${NODE_NAME}"
printf '%s\n' "${VLESS_URI}" > "${VLESS_FILE}"
chmod 644 "${VLESS_FILE}"

echo "[10/10] Configuring optional HTTP subscription hosting..."
SUBSCRIPTION_URL=""
configure_subscription

cat > "${INFO_FILE}" <<INFO_EOF
Server information:
Node role: Terminal
Server type: Xray VLESS Reality
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Node name: ${NODE_NAME}

VLESS Reality client:
UUID: ${UUID}
Flow: ${FLOW}
Network: tcp
Security: reality
SNI / ServerName: ${REALITY_SERVER_NAME}
Fingerprint: ${CLIENT_FINGERPRINT}
Public key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}
Reality dest: ${REALITY_DEST}

VLESS link:
${VLESS_URI}

Files:
${INFO_FILE}
${CLASH_FILE}
${VLESS_FILE}
${XRAY_CONFIG}
${REALITY_ENV_FILE}
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
To enable: ENABLE_SUBSCRIPTION=true bash terminal_reality.sh
INFO_SUB_EOF
fi

chmod 600 "${INFO_FILE}" "${REALITY_ENV_FILE}" "${XRAY_CONFIG}"
chmod 644 "${CLASH_FILE}" "${VLESS_FILE}"

echo ""
echo "=========================================="
echo "Setup complete"
echo "=========================================="
cat "${INFO_FILE}"

echo ""
echo "Xray status:"
systemctl status "${XRAY_SERVICE}" --no-pager || true

if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo ""
  echo "Nginx status:"
  systemctl status nginx --no-pager || true
fi

echo ""
echo "Listening ports:"
ss -tulnp | grep -E ":(${PORT}|${SUB_PORT})" || true

echo ""
echo "Important: allow TCP ${PORT} in your cloud firewall/security group."
echo "Reality over TCP does not need UDP ${PORT}."
if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo "Important: allow TCP ${SUB_PORT} if you want to access the subscription URL from outside."
  echo "Do not publish the subscription URL publicly; it contains your client config."
fi

echo ""
echo "VLESS Reality link:"
echo "${VLESS_URI}"

if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo ""
  echo "Clash subscription URL:"
  echo "${SUBSCRIPTION_URL}"
fi
