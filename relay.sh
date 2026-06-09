#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Relay Node: Direct Shadowsocks + Server-side Forwarding Setup v1.2
# This server provides two user-facing nodes:
#   1) Direct relay server node: client -> relay server
#   2) Forwarded terminal node: client -> relay server -> terminal server
#
# Required for forwarded node:
#   TARGET_IP, TARGET_PORT, TARGET_PASSWORD
# Optional:
#   TARGET_METHOD, DIRECT_PORT, FORWARD_PORT, NODE_NAME_DIRECT, NODE_NAME_FORWARD
# ==========================================================

DIRECT_PORT="${DIRECT_PORT:-443}"
FORWARD_PORT="${FORWARD_PORT:-8443}"
METHOD="${METHOD:-aes-256-gcm}"
TARGET_METHOD="${TARGET_METHOD:-aes-256-gcm}"
CONTAINER_NAME="${CONTAINER_NAME:-ss-server}"
IMAGE_NAME="${IMAGE_NAME:-shadowsocks/shadowsocks-libev}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-ss-relay}"
NODE_NAME_DIRECT="${NODE_NAME_DIRECT:-Relay-Direct}"
NODE_NAME_FORWARD="${NODE_NAME_FORWARD:-Terminal-via-Relay}"

TARGET_IP="${TARGET_IP:-}"
TARGET_PORT="${TARGET_PORT:-}"
TARGET_PASSWORD="${TARGET_PASSWORD:-}"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"
FORWARD_ENV_FILE="/etc/ss-relay-forward.env"

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
    apt install -y curl ca-certificates gnupg openssl iptables netcat-openbsd

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

    if [ -z "${public_ip}" ]; then
        candidate="$(curl -fsS -m 3 \
            -H "Metadata-Flavor: Google" \
            "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true)"
        if is_ipv4 "${candidate}"; then
            public_ip="${candidate}"
        fi
    fi

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
        public_ip="YOUR_RELAY_PUBLIC_IP"
        log "Warning: failed to detect public IPv4 automatically."
    fi

    echo "${public_ip}"
}

apply_forwarding_rules() {
    log "Applying TCP/UDP forwarding rules: relay:${FORWARD_PORT} -> ${TARGET_IP}:${TARGET_PORT}"

    cat > /etc/sysctl.d/99-ss-relay-forward.conf <<SYSCTL_EOF
net.ipv4.ip_forward=1
SYSCTL_EOF
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sysctl --system >/dev/null 2>&1 || true

    # NAT chains.
    iptables -t nat -N SS_RELAY_PRE 2>/dev/null || iptables -t nat -F SS_RELAY_PRE
    iptables -t nat -N SS_RELAY_POST 2>/dev/null || iptables -t nat -F SS_RELAY_POST
    iptables -t nat -C PREROUTING -j SS_RELAY_PRE 2>/dev/null || iptables -t nat -A PREROUTING -j SS_RELAY_PRE
    iptables -t nat -C POSTROUTING -j SS_RELAY_POST 2>/dev/null || iptables -t nat -A POSTROUTING -j SS_RELAY_POST

    iptables -t nat -A SS_RELAY_PRE -p tcp --dport "${FORWARD_PORT}" -j DNAT --to-destination "${TARGET_IP}:${TARGET_PORT}"
    iptables -t nat -A SS_RELAY_PRE -p udp --dport "${FORWARD_PORT}" -j DNAT --to-destination "${TARGET_IP}:${TARGET_PORT}"
    iptables -t nat -A SS_RELAY_POST -p tcp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j MASQUERADE
    iptables -t nat -A SS_RELAY_POST -p udp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j MASQUERADE

    # Filter chain: useful on hosts where Docker changes FORWARD policy.
    iptables -N SS_RELAY_FORWARD 2>/dev/null || iptables -F SS_RELAY_FORWARD
    iptables -C FORWARD -j SS_RELAY_FORWARD 2>/dev/null || iptables -I FORWARD 1 -j SS_RELAY_FORWARD
    iptables -A SS_RELAY_FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A SS_RELAY_FORWARD -p tcp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j ACCEPT
    iptables -A SS_RELAY_FORWARD -p udp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j ACCEPT

    cat > "${FORWARD_ENV_FILE}" <<ENV_EOF
TARGET_IP=${TARGET_IP}
TARGET_PORT=${TARGET_PORT}
FORWARD_PORT=${FORWARD_PORT}
ENV_EOF

    # Persist with a systemd unit instead of depending on iptables-persistent prompts.
    cat > /usr/local/sbin/ss-relay-restore.sh <<'RESTORE_EOF'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/ss-relay-forward.env"
[ -f "${ENV_FILE}" ] || exit 0
# shellcheck disable=SC1090
source "${ENV_FILE}"

iptables -t nat -N SS_RELAY_PRE 2>/dev/null || iptables -t nat -F SS_RELAY_PRE
iptables -t nat -N SS_RELAY_POST 2>/dev/null || iptables -t nat -F SS_RELAY_POST
iptables -t nat -C PREROUTING -j SS_RELAY_PRE 2>/dev/null || iptables -t nat -A PREROUTING -j SS_RELAY_PRE
iptables -t nat -C POSTROUTING -j SS_RELAY_POST 2>/dev/null || iptables -t nat -A POSTROUTING -j SS_RELAY_POST
iptables -t nat -A SS_RELAY_PRE -p tcp --dport "${FORWARD_PORT}" -j DNAT --to-destination "${TARGET_IP}:${TARGET_PORT}"
iptables -t nat -A SS_RELAY_PRE -p udp --dport "${FORWARD_PORT}" -j DNAT --to-destination "${TARGET_IP}:${TARGET_PORT}"
iptables -t nat -A SS_RELAY_POST -p tcp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j MASQUERADE
iptables -t nat -A SS_RELAY_POST -p udp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j MASQUERADE

iptables -N SS_RELAY_FORWARD 2>/dev/null || iptables -F SS_RELAY_FORWARD
iptables -C FORWARD -j SS_RELAY_FORWARD 2>/dev/null || iptables -I FORWARD 1 -j SS_RELAY_FORWARD
iptables -A SS_RELAY_FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A SS_RELAY_FORWARD -p tcp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j ACCEPT
iptables -A SS_RELAY_FORWARD -p udp -d "${TARGET_IP}" --dport "${TARGET_PORT}" -j ACCEPT
RESTORE_EOF
    chmod +x /usr/local/sbin/ss-relay-restore.sh

    cat > /etc/systemd/system/ss-relay-forward.service <<UNIT_EOF
[Unit]
Description=Restore SS relay forwarding rules
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ss-relay-restore.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT_EOF

    systemctl daemon-reload
    systemctl enable ss-relay-forward.service >/dev/null 2>&1 || true
}

if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script as root, for example:"
    echo "sudo TARGET_IP=1.2.3.4 TARGET_PORT=8388 TARGET_PASSWORD=xxx bash relay_node.sh"
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "Error: this script is designed for Ubuntu/Debian systems using apt."
    exit 1
fi

if [ -z "${TARGET_IP}" ] || [ -z "${TARGET_PORT}" ] || [ -z "${TARGET_PASSWORD}" ]; then
    echo "Error: TARGET_IP, TARGET_PORT, and TARGET_PASSWORD are required for relay mode."
    echo ""
    echo "Example:"
    echo "TARGET_IP=35.201.196.129 TARGET_PORT=8388 TARGET_PASSWORD='terminal_password' PORT=443 bash relay_node.sh"
    echo ""
    echo "Recommended cloud firewall/security group on this relay server:"
    echo "  TCP/UDP ${DIRECT_PORT} for direct relay node"
    echo "  TCP/UDP ${FORWARD_PORT} for forwarded terminal node"
    exit 1
fi

if ! is_ipv4 "${TARGET_IP}"; then
    echo "Error: TARGET_IP must be an IPv4 address, got: ${TARGET_IP}"
    exit 1
fi

log "======================================"
log " Relay Node Setup v1.2"
log " Direct node port: ${DIRECT_PORT}"
log " Forward node port: ${FORWARD_PORT}"
log " Target terminal: ${TARGET_IP}:${TARGET_PORT}"
log " Direct node name: ${NODE_NAME_DIRECT}"
log " Forward node name: ${NODE_NAME_FORWARD}"
log " Install directory: ${INSTALL_DIR}"
log "======================================"

mkdir -p "${INSTALL_DIR}"

log "[1/12] Updating apt package list..."
apt update -y

log "[2/12] Installing required packages and Docker..."
install_docker_if_needed

log "[3/12] Enabling BBR if supported..."
modprobe tcp_bbr 2>/dev/null || true
cat > /etc/sysctl.d/99-bbr.conf <<SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true
sysctl net.ipv4.tcp_congestion_control || true

log "[4/12] Enabling and starting Docker..."
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

log "[5/12] Generating direct relay Shadowsocks password..."
DIRECT_PASSWORD="$(openssl rand -hex 16)"

log "[6/12] Detecting relay public IPv4..."
RELAY_PUBLIC_IP="$(detect_public_ip)"
log "Detected relay public IPv4: ${RELAY_PUBLIC_IP}"

log "[7/12] Removing old direct Shadowsocks container if it exists..."
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

log "[8/12] Starting direct Shadowsocks container on relay server..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart always \
    -p "${DIRECT_PORT}:${DIRECT_PORT}/tcp" \
    -p "${DIRECT_PORT}:${DIRECT_PORT}/udp" \
    -e PASSWORD="${DIRECT_PASSWORD}" \
    -e METHOD="${METHOD}" \
    -e SERVER_ADDR="0.0.0.0" \
    -e SERVER_PORT="${DIRECT_PORT}" \
    -e TIMEOUT="300" \
    -e DNS_ADDRS="1.1.1.1,8.8.8.8" \
    "${IMAGE_NAME}"

sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || echo false)" != "true" ]; then
    echo "Error: direct Shadowsocks container failed to start."
    docker logs "${CONTAINER_NAME}" || true
    exit 1
fi

log "[9/12] Testing relay server connectivity to terminal node..."
if nc -vz -w 5 "${TARGET_IP}" "${TARGET_PORT}"; then
    log "Relay can reach terminal TCP ${TARGET_IP}:${TARGET_PORT}."
else
    log "Warning: relay could not confirm TCP connectivity to terminal ${TARGET_IP}:${TARGET_PORT}."
    log "The generated forwarded node may not work until terminal firewall/port is reachable."
fi

log "[10/12] Applying server-side TCP/UDP forwarding rules..."
apply_forwarding_rules

log "[11/12] Generating client configuration with direct and forwarded nodes..."
cat > "${INFO_FILE}" <<INFO_EOF
Node role: Relay
Relay server IP: ${RELAY_PUBLIC_IP}
Direct node port: ${DIRECT_PORT}
Direct node cipher: ${METHOD}
Direct node password: ${DIRECT_PASSWORD}
Direct node name: ${NODE_NAME_DIRECT}
Forward node public endpoint: ${RELAY_PUBLIC_IP}:${FORWARD_PORT}
Forward target terminal: ${TARGET_IP}:${TARGET_PORT}
Forward target cipher: ${TARGET_METHOD}
Forward target password: ${TARGET_PASSWORD}
Forward node name: ${NODE_NAME_FORWARD}
Docker container: ${CONTAINER_NAME}
Docker image: ${IMAGE_NAME}
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
  - name: "${NODE_NAME_DIRECT}"
    type: ss
    server: ${RELAY_PUBLIC_IP}
    port: ${DIRECT_PORT}
    cipher: ${METHOD}
    password: "${DIRECT_PASSWORD}"
    udp: true

  - name: "${NODE_NAME_FORWARD}"
    type: ss
    server: ${RELAY_PUBLIC_IP}
    port: ${FORWARD_PORT}
    cipher: ${TARGET_METHOD}
    password: "${TARGET_PASSWORD}"
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

log "[12/12] Generating ss:// links..."
DIRECT_USERINFO="$(printf '%s' "${METHOD}:${DIRECT_PASSWORD}" | base64_one_line | tr '+/' '-_' | sed 's/=*$//')"
DIRECT_SS_URI="ss://${DIRECT_USERINFO}@${RELAY_PUBLIC_IP}:${DIRECT_PORT}#${NODE_NAME_DIRECT}"
DIRECT_LEGACY_BASE64="$(printf '%s' "${METHOD}:${DIRECT_PASSWORD}@${RELAY_PUBLIC_IP}:${DIRECT_PORT}" | base64_one_line)"
DIRECT_LEGACY_URI="ss://${DIRECT_LEGACY_BASE64}#${NODE_NAME_DIRECT}"

FORWARD_USERINFO="$(printf '%s' "${TARGET_METHOD}:${TARGET_PASSWORD}" | base64_one_line | tr '+/' '-_' | sed 's/=*$//')"
FORWARD_SS_URI="ss://${FORWARD_USERINFO}@${RELAY_PUBLIC_IP}:${FORWARD_PORT}#${NODE_NAME_FORWARD}"
FORWARD_LEGACY_BASE64="$(printf '%s' "${TARGET_METHOD}:${TARGET_PASSWORD}@${RELAY_PUBLIC_IP}:${FORWARD_PORT}" | base64_one_line)"
FORWARD_LEGACY_URI="ss://${FORWARD_LEGACY_BASE64}#${NODE_NAME_FORWARD}"

cat > "${SS_FILE}" <<SS_EOF
Direct relay node SIP002:
${DIRECT_SS_URI}

Direct relay node Legacy:
${DIRECT_LEGACY_URI}

Forwarded terminal node SIP002:
${FORWARD_SS_URI}

Forwarded terminal node Legacy:
${FORWARD_LEGACY_URI}
SS_EOF

cat >> "${INFO_FILE}" <<INFO_EOF

Direct relay ss:// link:
${DIRECT_SS_URI}

Forwarded terminal ss:// link:
${FORWARD_SS_URI}
INFO_EOF

chmod 644 "${CLASH_FILE}" "${SS_FILE}"
chmod 600 "${INFO_FILE}"

log ""
log "======================================"
log " Relay setup complete"
log "======================================"
log "Server information:"
cat "${INFO_FILE}"
log ""
log "Docker status:"
docker ps | grep "${CONTAINER_NAME}" || true
log ""
log "Forwarding rules summary:"
log "${RELAY_PUBLIC_IP}:${FORWARD_PORT} -> ${TARGET_IP}:${TARGET_PORT}"
log ""
log "Files saved on relay server:"
log "${INFO_FILE}"
log "${CLASH_FILE}"
log "${SS_FILE}"
log ""
log "Important: allow these inbound ports on the relay server firewall/security group:"
log "TCP/UDP ${DIRECT_PORT}"
log "TCP/UDP ${FORWARD_PORT}"
log ""
log "Direct relay ss:// link:"
log "${DIRECT_SS_URI}"
log ""
log "Forwarded terminal ss:// link:"
log "${FORWARD_SS_URI}"
