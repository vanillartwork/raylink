#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Cloud VPS Shadowsocks + Clash Setup v1.1.1
# One-click Shadowsocks server with Clash config and ss:// links
# Works on AWS EC2, Google Cloud Compute Engine, and most Ubuntu VPS
# ==========================================================

PORT="8388"
METHOD="aes-256-gcm"
CONTAINER_NAME="ss-server"
IMAGE_NAME="shadowsocks/shadowsocks-libev"
INSTALL_DIR="/opt/aws-clash-ss"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"

NODE_NAME="AWS-SS"

echo "======================================"
echo " Cloud VPS Shadowsocks + Clash Setup v1.1.1"
echo " Port: ${PORT}"
echo " Method: ${METHOD}"
echo " Container: ${CONTAINER_NAME}"
echo " Image: ${IMAGE_NAME}"
echo " Install directory: ${INSTALL_DIR}"
echo "======================================"

if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script with sudo:"
    echo "sudo bash clash_ss.sh"
    exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
    echo "Error: this script is designed for Ubuntu/Debian systems using apt."
    exit 1
fi

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

mkdir -p "${INSTALL_DIR}"

echo "[1/10] Updating apt package list..."
apt update -y

echo "[2/10] Installing required packages..."
apt install -y curl ca-certificates gnupg openssl docker.io

echo "[3/10] Enabling BBR if supported..."

modprobe tcp_bbr 2>/dev/null || true

cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system >/dev/null 2>&1 || true

echo "Current TCP congestion control:"
sysctl net.ipv4.tcp_congestion_control || true

echo "[4/10] Enabling and starting Docker..."
systemctl enable docker
systemctl start docker

echo "[5/10] Generating Shadowsocks password..."
PASSWORD="$(openssl rand -hex 16)"

echo "[6/10] Detecting public IPv4..."

PUBLIC_IP=""

# Try AWS EC2 metadata.
TOKEN="$(curl -fsS -m 3 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

if [ -n "${TOKEN}" ]; then
    CANDIDATE_IP="$(curl -fsS -m 3 \
        -H "X-aws-ec2-metadata-token: ${TOKEN}" \
        "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"

    if is_ipv4 "${CANDIDATE_IP}"; then
        PUBLIC_IP="${CANDIDATE_IP}"
    fi
fi

# Try Google Cloud metadata.
if [ -z "${PUBLIC_IP}" ]; then
    CANDIDATE_IP="$(curl -fsS -m 3 \
        -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true)"

    if is_ipv4 "${CANDIDATE_IP}"; then
        PUBLIC_IP="${CANDIDATE_IP}"
    fi
fi

# Fallback to public IP services.
if [ -z "${PUBLIC_IP}" ]; then
    for IP_SERVICE in \
        "https://api.ipify.org" \
        "https://ifconfig.me" \
        "https://ipinfo.io/ip" \
        "http://4.ipw.cn"
    do
        CANDIDATE_IP="$(curl -4 -fsS -m 5 "${IP_SERVICE}" 2>/dev/null || true)"

        if is_ipv4 "${CANDIDATE_IP}"; then
            PUBLIC_IP="${CANDIDATE_IP}"
            break
        fi
    done
fi

if [ -z "${PUBLIC_IP}" ]; then
    PUBLIC_IP="YOUR_SERVER_PUBLIC_IP"
    echo "Warning: failed to detect public IPv4 automatically."
    echo "Please replace YOUR_SERVER_PUBLIC_IP in the generated Clash config manually."
fi

echo "Detected public IPv4: ${PUBLIC_IP}"

echo "[7/10] Removing old Shadowsocks container if it exists..."
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "[8/10] Starting Shadowsocks container..."

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
    echo ""
    echo "Error: Shadowsocks container failed to start."
    echo ""
    echo "Docker logs:"
    docker logs "${CONTAINER_NAME}" || true
    exit 1
fi

echo "[9/10] Generating Clash configuration..."

cat > "${INFO_FILE}" <<EOF
Server type: Shadowsocks
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Cipher: ${METHOD}
Password: ${PASSWORD}
Docker container: ${CONTAINER_NAME}
Docker image: ${IMAGE_NAME}
Node name: ${NODE_NAME}
EOF

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

echo "[10/10] Generating Shadowsocks ss:// links for mobile clients..."

# SIP002 format:
# ss://base64url(method:password)@server:port#name
SS_USERINFO="$(printf '%s' "${METHOD}:${PASSWORD}" | base64_one_line | tr '+/' '-_' | sed 's/=*$//')"
SS_URI="ss://${SS_USERINFO}@${PUBLIC_IP}:${PORT}#${NODE_NAME}"

# Legacy format:
# ss://base64(method:password@server:port)#name
SS_LEGACY_BASE64="$(printf '%s' "${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}" | base64_one_line)"
SS_LEGACY_URI="ss://${SS_LEGACY_BASE64}#${NODE_NAME}"

cat > "${SS_FILE}" <<EOF
SIP002:
${SS_URI}

Legacy:
${SS_LEGACY_URI}
EOF

cat >> "${INFO_FILE}" <<EOF

Mobile ss:// link:
${SS_URI}

Legacy ss:// link:
${SS_LEGACY_URI}
EOF

chmod 644 "${CLASH_FILE}" "${SS_FILE}"
chmod 600 "${INFO_FILE}"

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
echo "Docker status:"
docker ps | grep "${CONTAINER_NAME}" || true

echo ""
echo "Shadowsocks logs:"
docker logs "${CONTAINER_NAME}" || true

echo ""
echo "Files saved on server:"
echo "${INFO_FILE}"
echo "${CLASH_FILE}"
echo "${SS_FILE}"

echo ""
echo "Important:"
echo "Make sure your cloud firewall/security group allows:"
echo "TCP ${PORT} from 0.0.0.0/0"
echo "UDP ${PORT} from 0.0.0.0/0"
echo ""
echo "For SSH, keep port 22 limited to your own IP."

echo ""
echo "Mobile ss:// link:"
echo "${SS_URI}"
