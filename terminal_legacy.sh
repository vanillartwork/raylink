#!/usr/bin/env bash
set -euo pipefail

# Runtime options.
PORT="${PORT:-443}"
METHOD="${METHOD:-chacha20-ietf-poly1305}"
NODE_NAME="${NODE_NAME:-RayLink-SS}"
INSTALL_DIR="${INSTALL_DIR:-/opt/raylink-ss}"
CONTAINER_NAME="${CONTAINER_NAME:-raylink-ss}"
IMAGE_NAME="${IMAGE_NAME:-shadowsocks/shadowsocks-libev}"

# Generated files.
CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
SS_FILE="${INSTALL_DIR}/ss-uri.txt"
SS_URI_LIST_FILE="${INSTALL_DIR}/ss-uri-list"
SS_ENV_FILE="${INSTALL_DIR}/ss.env"

# Credential reuse.
PASSWORD="${PASSWORD:-}"
RESET_SS_CREDENTIALS="${RESET_SS_CREDENTIALS:-false}"

# DNS profile for generated Mihomo/Clash YAML.
DNS_PROFILE="${DNS_PROFILE:-mixed}"
DNS_EFFECTIVE_PROFILE=""

# Optional HTTP subscription hosting.
ENABLE_SUBSCRIPTION="${ENABLE_SUBSCRIPTION:-true}"
SUB_PORT="${SUB_PORT:-8080}"
SUB_TOKEN="${SUB_TOKEN:-}"
RESET_SUB_TOKEN="${RESET_SUB_TOKEN:-false}"
SUB_ROOT="${INSTALL_DIR}/public"
SUB_ENV_FILE="${INSTALL_DIR}/subscription.env"
NGINX_SITE="/etc/nginx/sites-available/raylink-ss-subscription"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/raylink-ss-subscription"
SUB_RATE_LIMIT="${SUB_RATE_LIMIT:-30r/m}"
SUB_RATE_BURST="${SUB_RATE_BURST:-10}"

is_true() {
  case "${1:-}" in
    true|TRUE|yes|YES|1|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

valid_ipv4() {
  local ip="${1:-}"
  local a b c d
  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "${ip}"
  for n in "$a" "$b" "$c" "$d"; do
    [[ "${n}" =~ ^[0-9]+$ ]] || return 1
    [ "${n}" -ge 0 ] && [ "${n}" -le 255 ] || return 1
  done
}

valid_public_ipv4() {
  local ip="${1:-}"
  local a b c d
  valid_ipv4 "${ip}" || return 1
  IFS=. read -r a b c d <<< "${ip}"

  [ "${a}" -eq 0 ] && return 1
  [ "${a}" -eq 10 ] && return 1
  [ "${a}" -eq 127 ] && return 1
  [ "${a}" -eq 169 ] && [ "${b}" -eq 254 ] && return 1
  [ "${a}" -eq 172 ] && [ "${b}" -ge 16 ] && [ "${b}" -le 31 ] && return 1
  [ "${a}" -eq 192 ] && [ "${b}" -eq 168 ] && return 1
  [ "${a}" -eq 100 ] && [ "${b}" -ge 64 ] && [ "${b}" -le 127 ] && return 1
  [ "${a}" -eq 192 ] && [ "${b}" -eq 0 ] && [ "${c}" -eq 2 ] && return 1
  [ "${a}" -eq 198 ] && { [ "${b}" -eq 18 ] || [ "${b}" -eq 19 ]; } && return 1
  [ "${a}" -eq 198 ] && [ "${b}" -eq 51 ] && [ "${c}" -eq 100 ] && return 1
  [ "${a}" -eq 203 ] && [ "${b}" -eq 0 ] && [ "${c}" -eq 113 ] && return 1
  [ "${a}" -ge 224 ] && return 1

  return 0
}

validate_port_number() {
  local name="$1"
  local value="$2"

  if ! printf '%s' "${value}" | grep -Eq '^[0-9]+$'; then
    echo "Error: ${name} must be a number between 1 and 65535, got: ${value}"
    exit 1
  fi

  if [ "${value}" -lt 1 ] || [ "${value}" -gt 65535 ]; then
    echo "Error: ${name} must be a number between 1 and 65535, got: ${value}"
    exit 1
  fi
}

load_kv_file_var() {
  local file="$1"
  local key="$2"

  [ -f "${file}" ] || {
    printf '\n'
    return 0
  }

  awk -v key="${key}" '
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34) }
    {
      eq = index($0, "=")
      if (eq > 0 && substr($0, 1, eq - 1) == key) {
        value = substr($0, eq + 1)
        while (length(value) >= 2) {
          first = substr(value, 1, 1)
          last = substr(value, length(value), 1)
          if ((first == sq && last == sq) || (first == dq && last == dq)) {
            value = substr(value, 2, length(value) - 2)
          } else {
            break
          }
        }
        print value
        found = 1
        exit
      }
    }
    END { if (!found) print "" }
  ' "${file}" 2>/dev/null || printf '\n'
}

write_kv_env_file() {
  local file="$1"
  shift
  : > "${file}"
  while [ "$#" -gt 0 ]; do
    local key="$1"
    local value="$2"
    shift 2
    printf "%s='%s'\n" "${key}" "${value}" >> "${file}"
  done
  chmod 600 "${file}"
}

validate_subscription_token() {
  local token="${1:-}"
  printf '%s' "${token}" | grep -Eq '^[A-Za-z0-9_-]{24,128}$'
}

base64_one_line() {
  if printf '' | base64 -w 0 >/dev/null 2>&1; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

urlencode() {
  local old_lc="${LC_ALL:-}"
  local LC_ALL=C
  local s="$1"
  local out=""
  local i c hex

  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "${c}" in
      [a-zA-Z0-9.~_-]) out+="${c}" ;;
      *) printf -v hex '%%%02X' "'${c}"; out+="${hex}" ;;
    esac
  done

  if [ -n "${old_lc}" ]; then
    LC_ALL="${old_lc}"
  else
    unset LC_ALL || true
  fi
  printf '%s' "${out}"
}

install_required_packages() {
  local packages=(ca-certificates curl openssl docker.io)

  command -v grep >/dev/null 2>&1 || packages+=(grep)
  command -v awk >/dev/null 2>&1 || packages+=(gawk)
  command -v ss >/dev/null 2>&1 || packages+=(iproute2)
  command -v base64 >/dev/null 2>&1 || packages+=(coreutils)

  if is_true "${ENABLE_SUBSCRIPTION}"; then
    command -v nginx >/dev/null 2>&1 || packages+=(nginx)
  fi

  apt update
  apt install -y "${packages[@]}"
}

enable_bbr_if_available() {
  modprobe tcp_bbr 2>/dev/null || true

  cat > /etc/sysctl.d/99-raylink-bbr.conf <<'SYSCTL_EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF

  sysctl --system >/dev/null 2>&1 || true
  sysctl net.ipv4.tcp_congestion_control || true
}

detect_public_ipv4() {
  if [ -n "${PUBLIC_IP:-}" ]; then
    printf '%s\n' "${PUBLIC_IP}"
    return 0
  fi

  local token candidate_ip url

  token="$(curl -fsS -m 3 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"

  if [ -n "${token}" ]; then
    candidate_ip="$(curl -fsS -m 3 \
      -H "X-aws-ec2-metadata-token: ${token}" \
      "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"
    candidate_ip="$(printf '%s' "${candidate_ip}" | tr -d ' \r\n\t')"
    if valid_public_ipv4 "${candidate_ip}"; then
      printf '%s\n' "${candidate_ip}"
      return 0
    fi
  fi

  candidate_ip="$(curl -fsS -m 3 \
    -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" 2>/dev/null || true)"
  candidate_ip="$(printf '%s' "${candidate_ip}" | tr -d ' \r\n\t')"
  if valid_public_ipv4 "${candidate_ip}"; then
    printf '%s\n' "${candidate_ip}"
    return 0
  fi

  for url in \
    "https://api.ipify.org" \
    "https://ipv4.icanhazip.com" \
    "https://checkip.amazonaws.com" \
    "https://ident.me" \
    "https://ipinfo.io/ip" \
    "https://ifconfig.me" \
    "http://4.ipw.cn"; do
    candidate_ip="$(curl -4 -fsS -m 6 "${url}" 2>/dev/null | tr -d ' \r\n\t' | head -c 64 || true)"
    if valid_public_ipv4 "${candidate_ip}"; then
      printf '%s\n' "${candidate_ip}"
      return 0
    fi
  done

  return 1
}

load_or_generate_password() {
  local input_password
  input_password="${PASSWORD:-}"

  if is_true "${RESET_SS_CREDENTIALS}"; then
    rm -f "${SS_ENV_FILE}"
  fi

  if [ -f "${SS_ENV_FILE}" ]; then
    PASSWORD="${PASSWORD:-$(load_kv_file_var "${SS_ENV_FILE}" PASSWORD)}"
  fi

  [ -n "${input_password}" ] && PASSWORD="${input_password}"

  if [ -z "${PASSWORD}" ]; then
    PASSWORD="$(openssl rand -base64 24 | tr -d '\r\n')"
  fi

  write_kv_env_file "${SS_ENV_FILE}" \
    PASSWORD "${PASSWORD}" \
    METHOD "${METHOD}" \
    PORT "${PORT}" \
    NODE_NAME "${NODE_NAME}"
}

validate_inputs() {
  validate_port_number "PORT" "${PORT}"
  validate_port_number "SUB_PORT" "${SUB_PORT}"

  if [ "${PORT}" = "${SUB_PORT}" ] && is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Error: PORT and SUB_PORT cannot be the same when subscription hosting is enabled."
    exit 1
  fi

  if ! printf '%s' "${METHOD}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: METHOD contains invalid characters: ${METHOD}"
    exit 1
  fi

  if ! printf '%s' "${NODE_NAME}" | grep -Eq '^[A-Za-z0-9._ -]+$'; then
    echo "Error: NODE_NAME contains invalid characters: ${NODE_NAME}"
    exit 1
  fi
}

resolve_dns_profile() {
  local requested
  requested="$(printf '%s' "${DNS_PROFILE:-mixed}" | tr '[:upper:]' '[:lower:]')"

  case "${requested}" in
    mixed|cn|china)
      DNS_EFFECTIVE_PROFILE="mixed"
      ;;
    domestic|return|home|backhome|china-home)
      DNS_EFFECTIVE_PROFILE="domestic"
      ;;
    foreign|global|world|overseas|abroad)
      DNS_EFFECTIVE_PROFILE="foreign"
      ;;
    minimal|compat|compatible)
      DNS_EFFECTIVE_PROFILE="minimal"
      ;;
    *)
      echo "Unknown DNS_PROFILE=${DNS_PROFILE}. Valid values: mixed, domestic, foreign, minimal."
      exit 1
      ;;
  esac

  echo "DNS profile selected: ${DNS_EFFECTIVE_PROFILE}"
}

write_dns_config() {
  case "${DNS_EFFECTIVE_PROFILE:-mixed}" in
    domestic)
      cat <<'DNS_EOF'
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
DNS_EOF
      ;;
    minimal)
      cat <<'DNS_EOF'
dns:
  enable: true
  ipv6: false
  enhanced-mode: redir-host
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://cloudflare-dns.com/dns-query
    - https://dns.google/dns-query
DNS_EOF
      ;;
    foreign)
      cat <<'DNS_EOF'
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://cloudflare-dns.com/dns-query
    - https://dns.google/dns-query
DNS_EOF
      ;;
    mixed|*)
      cat <<'DNS_EOF'
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver-policy:
    'geosite:cn,private':
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query
  nameserver:
    - https://cloudflare-dns.com/dns-query
    - https://dns.google/dns-query
DNS_EOF
      ;;
  esac
}

restart_docker_service() {
  systemctl enable docker
  systemctl start docker
}

start_shadowsocks_container() {
  docker stop "${CONTAINER_NAME}" 2>/dev/null || true
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true

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
}

generate_ss_uris() {
  local ss_userinfo ss_legacy_base64 encoded_name
  encoded_name="$(urlencode "${NODE_NAME}")"

  ss_userinfo="$(printf '%s' "${METHOD}:${PASSWORD}" | base64_one_line | tr '+/' '-_' | sed 's/=*$//')"
  SS_URI="ss://${ss_userinfo}@${PUBLIC_IP}:${PORT}#${encoded_name}"

  ss_legacy_base64="$(printf '%s' "${METHOD}:${PASSWORD}@${PUBLIC_IP}:${PORT}" | base64_one_line)"
  SS_LEGACY_URI="ss://${ss_legacy_base64}#${encoded_name}"
}

write_clash_config() {
  cat > "${CLASH_FILE}" <<CLASH_HEADER_EOF
mixed-port: 7890
allow-lan: false
mode: global
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true

CLASH_HEADER_EOF

  write_dns_config >> "${CLASH_FILE}"

  cat >> "${CLASH_FILE}" <<CLASH_EOF

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
      - "${NODE_NAME}"
      - DIRECT

rules:
  - MATCH,GLOBAL
CLASH_EOF

  chmod 644 "${CLASH_FILE}"
}

write_ss_files() {
  cat > "${SS_FILE}" <<SS_EOF
SIP002:
${SS_URI}

Legacy:
${SS_LEGACY_URI}
SS_EOF

  printf '%s\n' "${SS_URI}" | base64_one_line > "${SS_URI_LIST_FILE}"
  printf '\n' >> "${SS_URI_LIST_FILE}"

  chmod 644 "${SS_FILE}" "${SS_URI_LIST_FILE}"
}

write_info_file() {
  cat > "${INFO_FILE}" <<INFO_EOF
Server type: Shadowsocks
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Cipher: ${METHOD}
Password: ${PASSWORD}
Docker container: ${CONTAINER_NAME}
Docker image: ${IMAGE_NAME}
Node name: ${NODE_NAME}
DNS profile: ${DNS_EFFECTIVE_PROFILE}
HTTP subscription: ${ENABLE_SUBSCRIPTION}
INFO_EOF

  if is_true "${ENABLE_SUBSCRIPTION}"; then
    cat >> "${INFO_FILE}" <<INFO_EOF
Subscription URL universal: ${SUBSCRIPTION_URL_UNIVERSAL:-}
Subscription URL Clash: ${SUBSCRIPTION_URL_CLASH:-}
Subscription URL SS: ${SUBSCRIPTION_URL_SS:-}
INFO_EOF
  fi

  cat >> "${INFO_FILE}" <<INFO_EOF

Mobile ss:// link:
${SS_URI}

Legacy ss:// link:
${SS_LEGACY_URI}
INFO_EOF

  chmod 600 "${INFO_FILE}"
}

load_or_generate_subscription_token() {
  if ! is_true "${ENABLE_SUBSCRIPTION}"; then
    return 0
  fi

  local input_token
  input_token="${SUB_TOKEN:-}"

  if is_true "${RESET_SUB_TOKEN}"; then
    rm -f "${SUB_ENV_FILE}"
  fi

  if [ -f "${SUB_ENV_FILE}" ]; then
    SUB_TOKEN="${SUB_TOKEN:-$(load_kv_file_var "${SUB_ENV_FILE}" SUB_TOKEN)}"
  fi

  [ -n "${input_token}" ] && SUB_TOKEN="${input_token}"

  if [ -z "${SUB_TOKEN}" ]; then
    SUB_TOKEN="$(openssl rand -hex 24)"
  fi

  if ! validate_subscription_token "${SUB_TOKEN}"; then
    echo "Error: SUB_TOKEN must be 24-128 chars and contain only A-Z a-z 0-9 _ -"
    exit 1
  fi

  SUBSCRIPTION_URL_UNIVERSAL="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}"
  SUBSCRIPTION_URL_CLASH="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}/clash.yaml"
  SUBSCRIPTION_URL_SS="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}/ss"

  write_kv_env_file "${SUB_ENV_FILE}" \
    SUB_TOKEN "${SUB_TOKEN}" \
    SUB_PORT "${SUB_PORT}" \
    SUBSCRIPTION_URL_UNIVERSAL "${SUBSCRIPTION_URL_UNIVERSAL}" \
    SUBSCRIPTION_URL_CLASH "${SUBSCRIPTION_URL_CLASH}" \
    SUBSCRIPTION_URL_SS "${SUBSCRIPTION_URL_SS}"
}

write_subscription_files() {
  if ! is_true "${ENABLE_SUBSCRIPTION}"; then
    return 0
  fi

  mkdir -p "${SUB_ROOT}/sub/${SUB_TOKEN}"
  cp "${CLASH_FILE}" "${SUB_ROOT}/sub/${SUB_TOKEN}/clash.yaml"
  cp "${SS_URI_LIST_FILE}" "${SUB_ROOT}/sub/${SUB_TOKEN}/ss"
  cp "${SS_URI_LIST_FILE}" "${SUB_ROOT}/sub/${SUB_TOKEN}/ss.txt"
  cp "${SS_URI_LIST_FILE}" "${SUB_ROOT}/sub/${SUB_TOKEN}/index"
  chmod -R 755 "${SUB_ROOT}"
}

configure_subscription_nginx() {
  if ! is_true "${ENABLE_SUBSCRIPTION}"; then
    rm -f "${NGINX_SITE_LINK}"
    systemctl reload nginx >/dev/null 2>&1 || true
    return 0
  fi

  cat > "${NGINX_SITE}" <<NGINX_EOF
server {
    listen ${SUB_PORT};
    listen [::]:${SUB_PORT};
    server_name _;

    root ${SUB_ROOT};
    autoindex off;

    limit_req_zone \$binary_remote_addr zone=raylink_ss_sub_limit:10m rate=${SUB_RATE_LIMIT};

    location = / {
        return 404;
    }

    location ~ "^/sub/[A-Za-z0-9_-]{24,128}$" {
        limit_req zone=raylink_ss_sub_limit burst=${SUB_RATE_BURST} nodelay;
        default_type text/plain;
        try_files \$uri/index =404;
    }

    location ~ "^/sub/[A-Za-z0-9_-]{24,128}/clash\\.yaml$" {
        limit_req zone=raylink_ss_sub_limit burst=${SUB_RATE_BURST} nodelay;
        default_type text/yaml;
        try_files \$uri =404;
    }

    location ~ "^/sub/[A-Za-z0-9_-]{24,128}/ss(\\.txt)?$" {
        limit_req zone=raylink_ss_sub_limit burst=${SUB_RATE_BURST} nodelay;
        default_type text/plain;
        try_files \$uri =404;
    }
}
NGINX_EOF

  ln -sf "${NGINX_SITE}" "${NGINX_SITE_LINK}"
  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

check_listening_ports() {
  echo "Listening ports:"
  ss -ltnp | grep -E ":(${PORT}|${SUB_PORT})" || true
}

print_summary() {
  echo ""
  echo "======================================"
  echo " RayLink Shadowsocks backup setup complete"
  echo "======================================"
  echo ""

  echo "Server information:"
  cat "${INFO_FILE}"

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
  echo "${SS_URI_LIST_FILE}"

  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo ""
    echo "Subscription URLs:"
    echo "Universal URI-list: ${SUBSCRIPTION_URL_UNIVERSAL}"
    echo "Mihomo/Clash YAML: ${SUBSCRIPTION_URL_CLASH}"
    echo "SS URI-list: ${SUBSCRIPTION_URL_SS}"
  fi

  echo ""
  echo "Cloud firewall/security group should allow:"
  echo "TCP ${PORT} from 0.0.0.0/0"
  echo "UDP ${PORT} from 0.0.0.0/0"
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "TCP ${SUB_PORT} from your client IP, or 0.0.0.0/0 if you need public subscription access"
  fi
  echo "TCP 22 should be limited to your own IP."
}

main() {
  if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script with sudo."
    echo "Example: curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/ss.sh | sudo bash"
    exit 1
  fi

  if ! command -v apt >/dev/null 2>&1; then
    echo "Error: this script is designed for Ubuntu/Debian systems using apt."
    exit 1
  fi

  echo "======================================"
  echo " RayLink Shadowsocks backup setup"
  echo "======================================"
  echo "Port: ${PORT}"
  echo "Method: ${METHOD}"
  echo "Container: ${CONTAINER_NAME}"
  echo "Install directory: ${INSTALL_DIR}"
  echo "Node name: ${NODE_NAME}"
  echo "HTTP subscription: ${ENABLE_SUBSCRIPTION}"
  echo ""

  validate_inputs
  mkdir -p "${INSTALL_DIR}"

  echo "[1/10] Installing required packages..."
  install_required_packages

  echo "[2/10] Enabling BBR if available..."
  enable_bbr_if_available

  echo "[3/10] Starting Docker..."
  restart_docker_service

  echo "[4/10] Detecting public IPv4 and selecting DNS profile..."
  PUBLIC_IP="$(detect_public_ipv4 || true)"
  if [ -z "${PUBLIC_IP}" ]; then
    echo "Failed to detect public IPv4. You can rerun with PUBLIC_IP=x.x.x.x"
    exit 1
  fi
  echo "Public IPv4: ${PUBLIC_IP}"
  resolve_dns_profile

  echo "[5/10] Loading or generating Shadowsocks credentials..."
  load_or_generate_password

  echo "[6/10] Starting Shadowsocks container..."
  start_shadowsocks_container

  echo "[7/10] Generating client configuration files..."
  generate_ss_uris
  write_clash_config
  write_ss_files

  echo "[8/10] Configuring optional HTTP subscription hosting..."
  load_or_generate_subscription_token
  write_subscription_files
  configure_subscription_nginx

  echo "[9/10] Writing server information..."
  write_info_file

  echo "[10/10] Checking service status..."
  check_listening_ports

  print_summary
}

main "$@"
