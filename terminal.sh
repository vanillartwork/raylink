#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Terminal Node: Cloud VPS Shadowsocks + Clash Setup v1.2
# Generates one normal Shadowsocks node config.
# Works on AWS EC2, Google Cloud Compute Engine, Aliyun, and most Ubuntu/Debian VPS.
# ==========================================================

PORT="${PORT:-8388}"
METHOD="${METHOD:-aes-256-gcm}"
CONTAINER_NAME="${CONTAINER_NAME:-ss-server}"
IMAGE_NAME="${IMAGE_NAME:-shadowsocks/shadowsocks-libev}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-ss-clash}"
NODE_NAME="${NODE_NAME:-Terminal-SS}"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"

log() { echo "$*"; }

is_ipv4() {
    echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

base64_one_line() {
    if base64 --help 2>/dev/null | grep -q -- '-w'; then
        base64 -w 0
    else
        base64 | tr -d '\n'
    fi
}

install_docker_if_needed() {
    apt install -y curl ca-certificates gnupg openssl

    if command -v docker >/dev/null 2>&1; then
        log "Docker already installed: $(docker --version)"
        return 0
    fi

    if ! apt install -y docker.io; then
        log "Docker install failed. Trying to resolve common containerd conflict..."
        apt remove -y docker docker-engine docker.io containerd containerd.io runc || true
        apt autoremove -y || true
        mkdir -p /root/apt-source-backup
        mv /etc/apt/sources.list.d/*docker* /root/apt-source-backup/ 2>/dev/null || true
        apt update -y
        apt install -y docker.io
    fi
}

detect_public_ip() {
    local candidate token service
    local public_ip=""

    # AWS EC2 metadata.
    token="$(curl -fsS -m 3 -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

    if [ -n "${token}" ]; then
        candidate="$(curl -fsS -m 3 \
            -H "X-aws-ec2-metadata-token: ${token}" \
            "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"
        if is_ipv4 "${candidate}"; then
            public_ip="${candidate}"
        fi
    fi

    # Google Cloud metadata.
    if [ -z "${public_ip}" ]; then
        candidate="$(curl -fsS -m 3 \
            -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true)"
        if is_ipv4 "${candidate}"; then
            public_ip="${candidate}"
        fi
    fi

    # Public IP services.
    if [ -z "${public_ip}" ]; then
        for service in \
            "https://api.ipify.org" \
            "https://ifconfig.me" \
            "https://ipinfo.io/ip" \
            "http://4.ipw.cn"
        do
            candidate="$(curl -4 -fsS -m 5 "${service}" 2>/dev/null || true)"
            if is_ipv4 "${candidate}"; then
                public_ip="${candidate}"
                break
            fi
        done
    fi

    if [ -z "${public_ip}" ]; then
        public_ip="YOUR_SERVER_PUBLIC_IP"
        log "Warning: failed to detect public IPv4 automatically."
        log "Please replace YOUR_SERVER_PUBLIC_IP in generated files manually."
    fi

    echo "${public_ip}"
}

if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script as root, for example:"
    echo "sudo PORT=8388 bash terminal_node.sh"
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "Error: this script is designed for Ubuntu/Debian systems using apt."
    exit 1
fi

log "======================================"
log " Terminal Node Shadowsocks Setup v1.2"
log " Port: ${PORT}"
log " Method: ${METHOD}"
log " Node name: ${NODE_NAME}"
log " Install directory: ${INSTALL_DIR}"
log "======================================"

mkdir -p "${INSTALL_DIR}"

log "[1/10] Updating apt package list..."
apt update -y

log "[2/10] Installing required packages and Docker..."
install_docker_if_needed

log "[3/10] Enabling BBR if supported..."
modprobe tcp_bbr 2>/dev/null || true
cat > /etc/sysctl.d/99-bbr.conf <<SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true
sysctl net.ipv4.tcp_congestion_control || true

log "[4/10] Enabling and starting Docker..."
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

log "[5/10] Generating Shadowsocks password..."
PASSWORD="$(openssl rand -hex 16)"

log "[6/10] Detecting public IPv4..."
PUBLIC_IP="$(detect_public_ip)"
log "Detected public IPv4: ${PUBLIC_IP}"

log "[7/10] Removing old Shadowsocks container if it exists..."
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

log "[8/10] Starting Shadowsocks container..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart always \
    -p "${PORT}:${PORT}/tcp" \
    -p "${PORT}:${PORT}/udp" \
    -e PASSWORD="${PASSWORD}" \
    -e METHOD="${METHOD}" \
    -e SERVER_ADDR="0.0.0.0" \
    -e SERVER_PORT="${PORT}" \
    -e TIMEOUT="300" \
    -e DNS_ADDRS="1.1.1.1,8.8.8.8" \
    "${IMAGE_NAME}"

sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || echo false)" != "true" ]; then
    echo "Error: Shadowsocks container failed to start."
    docker logs "${CONTAINER_NAME}" || true
    exit 1
fi

log "[9/10] Generating client configuration..."
cat > "${INFO_FILE}" <<INFO_EOF
Node role: Terminal
Server type: Shadowsocks
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Cipher: ${METHOD}
Password: ${PASSWORD}
Docker container: ${CONTAINER_NAME}
Docker image: ${IMAGE_NAME}
Node name: ${NODE_NAME}
INFO_EOF

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
CLASH_EOF

log "[10/10] Generating ss:// links..."
SS_USERINFO="$(printf '%s' "${METHOD}:${PASSWORD}" | base64_one_line | tr '+/' '-_' | sed 's/=*$//')"
SS_URI="ss://${SS_USERINFO}@${PUBLIC_IP}:${PORT}#${NODE_NAME}"
SS_LEGACY_BASE64="$(printf '%s' "${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}" | base64_one_line)"
SS_LEGACY_URI="ss://${SS_LEGACY_BASE64}#${NODE_NAME}"

cat > "${SS_FILE}" <<SS_EOF
SIP002:
${SS_URI}

Legacy:
${SS_LEGACY_URI}
SS_EOF

cat >> "${INFO_FILE}" <<INFO_EOF

Mobile ss:// link:
${SS_URI}

Legacy ss:// link:
${SS_LEGACY_URI}
INFO_EOF

chmod 644 "${CLASH_FILE}" "${SS_FILE}"
chmod 600 "${INFO_FILE}"

log ""
log "======================================"
log " Setup complete"
log "======================================"
log "Server information:"
cat "${INFO_FILE}"
log ""
log "Docker status:"
docker ps | grep "${CONTAINER_NAME}" || true
log ""
log "Shadowsocks logs:"
docker logs "${CONTAINER_NAME}" || true
log ""
log "Files saved on server:"
log "${INFO_FILE}"
log "${CLASH_FILE}"
log "${SS_FILE}"
log ""
log "Important: allow TCP/UDP ${PORT} in your cloud firewall/security group."
log ""
log "Mobile ss:// link:"
log "${SS_URI}"
