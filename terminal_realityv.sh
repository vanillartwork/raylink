#!/usr/bin/env bash
set -euo pipefail

# Generic Xray VLESS Reality terminal node (hardened) with HTTP multi-format subscription hosting enabled by default.
# Features:
# - VLESS Reality terminal node
# - HTTP subscription hosting through nginx (enabled by default; set ENABLE_SUBSCRIPTION=false to disable)
#   /sub/{TOKEN}             → Universal URI-list (v2rayN / v2rayNG / Hiddify / Shadowrocket)
#   /sub/{TOKEN}/clash.yaml  → Mihomo / Clash Meta / FlClash / Clash Verge Rev
#   /sub/{TOKEN}/vless       → legacy compatibility alias for URI-list
#   /sub/{TOKEN}/vless.txt   → plain text, browser-friendly
# - Persistent UUID / Reality keys / shortId / client fingerprint
# - Public IPv4 auto detection with private-range filtering
# - Reality target TLS 1.3 sanity check
# - Basic TCP tuning for small VPS instances
# - Purpose-oriented DNS profiles for generated client YAML
# - Optional TCP Fast Open for Xray and Mihomo/Clash client config
# - Hardened systemd service (CAP_NET_BIND_SERVICE, NoNewPrivileges, ProtectSystem)
# - Safe env-file parsing (no source), subscription rate limiting

PORT="${PORT:-443}"
NODE_NAME="${NODE_NAME:-Terminal-Reality}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cloud-xray-terminal}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
XRAY_CONFIG="${XRAY_CONFIG:-${XRAY_CONFIG_DIR}/config.json}"
XRAY_SHARE_DIR="${XRAY_SHARE_DIR:-/usr/local/share/xray}"
XRAY_SERVICE="xray.service"
XRAY_SERVICE_USER="${XRAY_SERVICE_USER:-xray}"
XRAY_SERVICE_GROUP="${XRAY_SERVICE_GROUP:-xray}"
LISTEN_ADDRESS="${LISTEN_ADDRESS:-0.0.0.0}"

CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
VLESS_FILE="${INSTALL_DIR}/vless-uri.txt"
VLESS_URI_LIST_FILE="${INSTALL_DIR}/vless-uri-list"   # base64-encoded URI list for v2rayN/Hiddify/Shadowrocket
REALITY_ENV_FILE="${INSTALL_DIR}/reality.env"

# Reality settings.
# REALITY_SERVER_NAME should usually match the host part of REALITY_DEST.
# If these are left empty, saved values from ${REALITY_ENV_FILE} will be reused.
# If no saved values exist, defaults below will be used.
REALITY_DEST="${REALITY_DEST:-}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-}"
CLIENT_FINGERPRINT_POOL="${CLIENT_FINGERPRINT_POOL:-chrome firefox safari edge}"
FLOW="${FLOW:-}"

# TCP Fast Open. Enabled by default. Set ENABLE_TFO=false if a client or network path has compatibility issues.
ENABLE_TFO="${ENABLE_TFO:-true}"

# DNS profile for generated Mihomo/Clash YAML.
# The best DNS choice depends mainly on the sites you intend to visit, not only on VPS location.
# - mixed: default. General-purpose profile: foreign/global DNS by default, domestic DNS only for geosite:cn/private.
# - foreign: overseas node for mostly foreign/global websites.
# - domestic: return-home / China-oriented node for mostly Chinese websites.
# - minimal: compatibility-first redir-host DNS.
# - auto: optional legacy mode; choose domestic for selected server countries, otherwise foreign.
DNS_PROFILE="${DNS_PROFILE:-mixed}"
AUTO_DNS_DOMESTIC_COUNTRIES="${AUTO_DNS_DOMESTIC_COUNTRIES:-${AUTO_DNS_RETURN_COUNTRIES:-CN}}"
SERVER_COUNTRY="${SERVER_COUNTRY:-}"
DNS_DETECTED_COUNTRY=""
DNS_EFFECTIVE_PROFILE=""

# Check the target site with openssl s_client -tls1_3 before writing config.
# The check is non-fatal by default. Set REALITY_CHECK_STRICT=true to fail on check failure.
CHECK_REALITY_TARGET="${CHECK_REALITY_TARGET:-true}"
REALITY_CHECK_STRICT="${REALITY_CHECK_STRICT:-false}"
REALITY_CHECK_LOG="${REALITY_CHECK_LOG:-/tmp/reality_target_check.log}"

# Clash/Mihomo subscription hosting. Enabled by default.
# Set ENABLE_SUBSCRIPTION=false to disable and remove this script's managed nginx site link.
ENABLE_SUBSCRIPTION="${ENABLE_SUBSCRIPTION:-true}"
SUB_PORT="${SUB_PORT:-8080}"
SUB_TOKEN="${SUB_TOKEN:-}"
SUB_ROOT="${INSTALL_DIR}/public"
SUB_ENV_FILE="${INSTALL_DIR}/subscription.env"
NGINX_SITE="/etc/nginx/sites-available/cloud-xray-terminal-subscription"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/cloud-xray-terminal-subscription"
RESET_SUB_TOKEN="${RESET_SUB_TOKEN:-false}"
SUB_RATE_LIMIT="${SUB_RATE_LIMIT:-30r/m}"
SUB_RATE_BURST="${SUB_RATE_BURST:-10}"

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

  # Filter non-public ranges: RFC1918, loopback, link-local, CGNAT, documentation, benchmark, multicast/reserved.
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

install_required_packages() {
  local packages=(ca-certificates)

  command -v curl >/dev/null 2>&1 || packages+=(curl)
  command -v openssl >/dev/null 2>&1 || packages+=(openssl)
  command -v unzip >/dev/null 2>&1 || packages+=(unzip)
  command -v ss >/dev/null 2>&1 || packages+=(iproute2)
  command -v awk >/dev/null 2>&1 || packages+=(gawk)
  command -v grep >/dev/null 2>&1 || packages+=(grep)
  command -v timeout >/dev/null 2>&1 || packages+=(coreutils)
  command -v jq >/dev/null 2>&1 || packages+=(jq)
  command -v getent >/dev/null 2>&1 || packages+=(passwd)
  command -v useradd >/dev/null 2>&1 || packages+=(passwd)
  command -v groupadd >/dev/null 2>&1 || packages+=(passwd)

  # nginx is needed only when HTTP subscription hosting is enabled.
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    command -v nginx >/dev/null 2>&1 || packages+=(nginx)
  fi

  apt update
  apt install -y "${packages[@]}"
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
    if valid_public_ipv4 "${ip}"; then
      printf '%s\n' "${ip}"
      return 0
    fi
  done

  return 1
}

pick_random_fingerprint() {
  local pool_string="${CLIENT_FINGERPRINT_POOL:-chrome firefox safari edge}"
  local -a pool
  local count idx

  # shellcheck disable=SC2206
  pool=(${pool_string})
  count="${#pool[@]}"

  if [ "${count}" -eq 0 ]; then
    printf '%s\n' "chrome"
    return 0
  fi

  idx=$((RANDOM % count))
  printf '%s\n' "${pool[${idx}]}"
}

normalize_reality_target() {
  if [ -z "${REALITY_DEST}" ]; then
    REALITY_DEST="www.microsoft.com:443"
  fi

  if [ -z "${REALITY_SERVER_NAME}" ]; then
    REALITY_SERVER_NAME="${REALITY_DEST%%:*}"
  fi

  if [[ "${REALITY_DEST}" != *:* ]]; then
    REALITY_DEST="${REALITY_DEST}:443"
  fi
}

check_reality_target() {
  if ! is_true "${CHECK_REALITY_TARGET}"; then
    echo "Skip Reality target check because CHECK_REALITY_TARGET=false"
    return 0
  fi

  local dest_host dest_port
  dest_host="${REALITY_DEST%%:*}"
  dest_port="${REALITY_DEST##*:}"

  if [ -z "${dest_host}" ] || [ -z "${dest_port}" ] || [ "${dest_host}" = "${dest_port}" ]; then
    echo "Warning: invalid REALITY_DEST=${REALITY_DEST}; expected host:port."
    if is_true "${REALITY_CHECK_STRICT}"; then
      exit 1
    fi
    return 0
  fi

  echo "Checking Reality target with TLS 1.3: ${REALITY_SERVER_NAME} -> ${dest_host}:${dest_port}"

  if timeout 10 openssl s_client \
    -connect "${dest_host}:${dest_port}" \
    -servername "${REALITY_SERVER_NAME}" \
    -tls1_3 \
    </dev/null >"${REALITY_CHECK_LOG}" 2>&1; then
    echo "Reality target TLS 1.3 check passed."
    return 0
  fi

  echo "Warning: Reality target TLS 1.3 check failed."
  echo "Check log: ${REALITY_CHECK_LOG}"
  echo "You can still continue, but consider changing REALITY_DEST / REALITY_SERVER_NAME."

  if is_true "${REALITY_CHECK_STRICT}"; then
    exit 1
  fi

  return 0
}


detect_server_country_code() {
  if [ -n "${SERVER_COUNTRY:-}" ]; then
    printf '%s\n' "${SERVER_COUNTRY}" | tr '[:lower:]' '[:upper:]' | head -c 2
    return 0
  fi

  local url country
  for url in \
    "https://ipinfo.io/${PUBLIC_IP}/country" \
    "https://ipapi.co/${PUBLIC_IP}/country/" \
    "http://ip-api.com/line/${PUBLIC_IP}?fields=countryCode"; do
    country="$(curl -4 -fsS -m 6 "${url}" 2>/dev/null | tr -dc 'A-Za-z' | tr '[:lower:]' '[:upper:]' | head -c 2 || true)"
    if printf '%s' "${country}" | grep -Eq '^[A-Z]{2}$'; then
      printf '%s\n' "${country}"
      return 0
    fi
  done

  return 1
}

country_in_auto_domestic_list() {
  local country="${1:-}"
  local item
  for item in ${AUTO_DNS_DOMESTIC_COUNTRIES}; do
    if [ "${country}" = "$(printf '%s' "${item}" | tr '[:lower:]' '[:upper:]')" ]; then
      return 0
    fi
  done
  return 1
}

resolve_dns_profile() {
  local requested
  requested="$(printf '%s' "${DNS_PROFILE:-mixed}" | tr '[:upper:]' '[:lower:]')"

  case "${requested}" in
    foreign|global|world|overseas|abroad)
      DNS_EFFECTIVE_PROFILE="foreign"
      ;;
    domestic|return|home|backhome|china-home)
      DNS_EFFECTIVE_PROFILE="domestic"
      ;;
    mixed|cn|china)
      DNS_EFFECTIVE_PROFILE="mixed"
      ;;
    minimal|compat|compatible)
      DNS_EFFECTIVE_PROFILE="minimal"
      ;;
    auto)
      DNS_DETECTED_COUNTRY="$(detect_server_country_code || true)"
      if [ -n "${DNS_DETECTED_COUNTRY}" ] && country_in_auto_domestic_list "${DNS_DETECTED_COUNTRY}"; then
        DNS_EFFECTIVE_PROFILE="domestic"
      else
        DNS_EFFECTIVE_PROFILE="foreign"
      fi
      ;;
    "")
      DNS_EFFECTIVE_PROFILE="mixed"
      ;;
    *)
      echo "Unknown DNS_PROFILE=${DNS_PROFILE}. Valid values: mixed, foreign, domestic, minimal, auto."
      echo "Aliases: global/world/overseas -> foreign; return/home/backhome -> domestic; cn/china -> mixed."
      exit 1
      ;;
  esac

  if [ -z "${DNS_DETECTED_COUNTRY}" ]; then
    DNS_DETECTED_COUNTRY="not-used"
  fi

  echo "DNS profile requested: ${DNS_PROFILE}"
  echo "DNS profile selected: ${DNS_EFFECTIVE_PROFILE}"
  echo "Server country detected: ${DNS_DETECTED_COUNTRY}"
}
write_dns_config() {
  case "${DNS_EFFECTIVE_PROFILE:-mixed}" in
    mixed)
      cat <<'DNS_EOF'
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '*.localhost'
    - localhost
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
    - 1.1.1.1
    - 8.8.8.8
  nameserver-policy:
    'geosite:cn,private':
      - https://dns.alidns.com/dns-query
      - https://doh.pub/dns-query
  nameserver:
    - https://cloudflare-dns.com/dns-query
    - https://dns.google/dns-query
DNS_EOF
      ;;
    domestic)
      cat <<'DNS_EOF'
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '*.localhost'
    - localhost
    - '*.msftconnecttest.com'
    - '*.msftncsi.com'
    - 'time.*.com'
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
    foreign|*)
      cat <<'DNS_EOF'
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '*.localhost'
    - localhost
    - '*.msftconnecttest.com'
    - '*.msftncsi.com'
    - 'time.*.com'
    - 'time.*.apple.com'
    - '*.pool.ntp.org'
    - '+.stun.*.*'
    - '+.stun.*.*.*'
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://cloudflare-dns.com/dns-query
    - https://dns.google/dns-query
DNS_EOF
      ;;
  esac
}

install_xray() {
  if [ -x "${XRAY_BIN}" ]; then
    "${XRAY_BIN}" version || true
    return 0
  fi

  echo "Installing Xray-core from GitHub latest release..."

  local arch xray_arch tmp_dir release_json download_url found_bin prev_exit_trap_action
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

  # Preserve any existing EXIT trap. Do not use eval on the full trap -p output.
  prev_exit_trap_action="$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//" || true)"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT
  cd "${tmp_dir}"

  release_json="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest)"
  if command -v jq >/dev/null 2>&1; then
    download_url="$(printf '%s' "${release_json}" | jq -r ".assets[] | select(.name | test(\"Xray-linux-${xray_arch}\\\\.zip\")) | .browser_download_url" | head -n 1)"
    [ "${download_url}" = "null" ] && download_url=""
  else
    download_url="$(printf '%s' "${release_json}" | grep -oE "https://[^\"]+Xray-linux-${xray_arch}\.zip" | head -n 1)"
  fi

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
  tmp_dir=""

  if [ -n "${prev_exit_trap_action}" ]; then
    trap "${prev_exit_trap_action}" EXIT
  else
    trap - EXIT
  fi

  "${XRAY_BIN}" version || true
}
load_kv_file_var() {
  local file="$1"
  local key="$2"

  [ -f "${file}" ] || {
    printf '\n'
    return 0
  }

  # Safe key=value parser. It never sources the file and preserves every
  # character after the first '='. Older buggy versions could repeatedly wrap
  # saved values in quotes on each rerun, so matching outer quote pairs are
  # removed repeatedly to repair those files automatically.
  awk -v key="${key}" '
    BEGIN {
      sq = sprintf("%c", 39)
      dq = sprintf("%c", 34)
    }
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
    END {
      if (!found) print ""
    }
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
    # Values generated by this script are token-like. If users pass unusual values, keep them literal.
    printf "%s='%s'\n" "${key}" "${value}" >> "${file}"
  done
  chmod 600 "${file}"
}

warn_if_unexpected_x25519_key() {
  local label="$1"
  local value="$2"
  if ! printf '%s' "${value}" | grep -Eq '^[A-Za-z0-9_-]{40,50}$'; then
    echo "Warning: ${label} format looks unexpected: ${value:0:10}..."
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
ensure_xray_service_identity() {
  if ! getent group "${XRAY_SERVICE_GROUP}" >/dev/null 2>&1; then
    groupadd --system "${XRAY_SERVICE_GROUP}"
  fi

  if ! getent passwd "${XRAY_SERVICE_USER}" >/dev/null 2>&1; then
    useradd --system \
      --no-create-home \
      --shell /usr/sbin/nologin \
      --gid "${XRAY_SERVICE_GROUP}" \
      "${XRAY_SERVICE_USER}"
  else
    local actual_gid expected_gid
    actual_gid="$(id -g "${XRAY_SERVICE_USER}" 2>/dev/null || echo "")"
    expected_gid="$(getent group "${XRAY_SERVICE_GROUP}" | cut -d: -f3)"

    if [ -n "${actual_gid}" ] && [ -n "${expected_gid}" ] && [ "${actual_gid}" != "${expected_gid}" ]; then
      echo "Warning: user ${XRAY_SERVICE_USER} exists but primary gid (${actual_gid}) != ${XRAY_SERVICE_GROUP} gid (${expected_gid})."
      echo "The xray config file may not be readable with chmod 640."
      echo "Consider fixing the user/group manually, or set XRAY_SERVICE_USER / XRAY_SERVICE_GROUP explicitly."
    fi
  fi
}
load_or_generate_reality_credentials() {
  local input_uuid input_private_key input_public_key input_short_id
  local input_reality_dest input_reality_server_name input_client_fingerprint input_flow

  input_uuid="${UUID:-}"
  input_private_key="${PRIVATE_KEY:-}"
  input_public_key="${PUBLIC_KEY:-}"
  input_short_id="${SHORT_ID:-}"
  input_reality_dest="${REALITY_DEST:-}"
  input_reality_server_name="${REALITY_SERVER_NAME:-}"
  input_client_fingerprint="${CLIENT_FINGERPRINT:-}"
  input_flow="${FLOW:-}"

  if is_true "${RESET_REALITY_CREDENTIALS}"; then
    rm -f "${REALITY_ENV_FILE}"
  fi

  # Do not source ${REALITY_ENV_FILE}. It is parsed as key=value text to avoid executing modified content.
  if [ -f "${REALITY_ENV_FILE}" ]; then
    UUID="${UUID:-$(load_kv_file_var "${REALITY_ENV_FILE}" UUID)}"
    PRIVATE_KEY="${PRIVATE_KEY:-$(load_kv_file_var "${REALITY_ENV_FILE}" PRIVATE_KEY)}"
    PUBLIC_KEY="${PUBLIC_KEY:-$(load_kv_file_var "${REALITY_ENV_FILE}" PUBLIC_KEY)}"
    SHORT_ID="${SHORT_ID:-$(load_kv_file_var "${REALITY_ENV_FILE}" SHORT_ID)}"
    REALITY_DEST="${REALITY_DEST:-$(load_kv_file_var "${REALITY_ENV_FILE}" REALITY_DEST)}"
    REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-$(load_kv_file_var "${REALITY_ENV_FILE}" REALITY_SERVER_NAME)}"
    CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-$(load_kv_file_var "${REALITY_ENV_FILE}" CLIENT_FINGERPRINT)}"
    FLOW="${FLOW:-$(load_kv_file_var "${REALITY_ENV_FILE}" FLOW)}"
  fi

  # Explicit environment variables from this run should override saved values.
  [ -n "${input_uuid}" ] && UUID="${input_uuid}"
  [ -n "${input_private_key}" ] && PRIVATE_KEY="${input_private_key}"
  [ -n "${input_public_key}" ] && PUBLIC_KEY="${input_public_key}"
  [ -n "${input_short_id}" ] && SHORT_ID="${input_short_id}"
  [ -n "${input_reality_dest}" ] && REALITY_DEST="${input_reality_dest}"
  [ -n "${input_reality_server_name}" ] && REALITY_SERVER_NAME="${input_reality_server_name}"
  [ -n "${input_client_fingerprint}" ] && CLIENT_FINGERPRINT="${input_client_fingerprint}"
  [ -n "${input_flow}" ] && FLOW="${input_flow}"

  FLOW="${FLOW:-xtls-rprx-vision}"
  normalize_reality_target

  if [ -z "${CLIENT_FINGERPRINT}" ]; then
    CLIENT_FINGERPRINT="$(pick_random_fingerprint)"
    echo "Generated client fingerprint: ${CLIENT_FINGERPRINT}"
  else
    echo "Using client fingerprint: ${CLIENT_FINGERPRINT}"
  fi

  if [ -z "${UUID}" ]; then
    UUID="$(${XRAY_BIN} uuid | tr -d ' \r\n\t')"
  fi

  if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ]; then
    local keypair
    keypair="$(${XRAY_BIN} x25519)"

    # Known xray x25519 outputs:
    #   Private key: xxx
    #   Public key: xxx
    #   PrivateKey: xxx
    #   Password (PublicKey): xxx
    #   Hash32: xxx
    PRIVATE_KEY="$(printf '%s\n' "${keypair}" | awk -F':[[:space:]]*' 'tolower($1) ~ /^private[[:space:]]*key$/ || tolower($1) ~ /^privatekey$/ {print $2; exit}' | tr -d ' \r\n\t')"
    PUBLIC_KEY="$(printf '%s\n' "${keypair}" | awk -F':[[:space:]]*' 'tolower($1) ~ /^public[[:space:]]*key$/ || tolower($1) ~ /^publickey$/ || tolower($1) ~ /^password[[:space:]]*\(publickey\)$/ {print $2; exit}' | tr -d ' \r\n\t')"

    if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ]; then
      echo "Failed to parse Reality x25519 key pair."
      echo "xray x25519 output was:"
      printf '%s\n' "${keypair}"
      exit 1
    fi
  fi

  warn_if_unexpected_x25519_key "PRIVATE_KEY" "${PRIVATE_KEY}"
  warn_if_unexpected_x25519_key "PUBLIC_KEY" "${PUBLIC_KEY}"

  if [ -z "${SHORT_ID}" ]; then
    SHORT_ID="$(openssl rand -hex 8)"
  fi

  if [ -z "${UUID}" ] || [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ] || [ -z "${SHORT_ID}" ]; then
    echo "Failed to generate Reality credentials."
    exit 1
  fi

  write_kv_env_file "${REALITY_ENV_FILE}" \
    UUID "${UUID}" \
    PRIVATE_KEY "${PRIVATE_KEY}" \
    PUBLIC_KEY "${PUBLIC_KEY}" \
    SHORT_ID "${SHORT_ID}" \
    REALITY_DEST "${REALITY_DEST}" \
    REALITY_SERVER_NAME "${REALITY_SERVER_NAME}" \
    CLIENT_FINGERPRINT "${CLIENT_FINGERPRINT}" \
    FLOW "${FLOW}"
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


validate_reality_inputs() {
  validate_port_number PORT "${PORT}"

  if ! printf '%s' "${UUID}" | grep -Eq '^[0-9a-fA-F-]{36}$'; then
    echo "Error: UUID format is invalid: ${UUID}"
    exit 1
  fi

  if ! printf '%s' "${PRIVATE_KEY}" | grep -Eq '^[A-Za-z0-9_-]{40,60}$'; then
    echo "Error: PRIVATE_KEY format is invalid or contains unsafe characters."
    exit 1
  fi

  if ! printf '%s' "${PUBLIC_KEY}" | grep -Eq '^[A-Za-z0-9_-]{40,60}$'; then
    echo "Error: PUBLIC_KEY format is invalid or contains unsafe characters."
    exit 1
  fi

  # SHORT_ID can technically be empty in Xray Reality, but this script generates
  # a 16-hex shortId by default for clearer client configuration.
  if ! printf '%s' "${SHORT_ID}" | grep -Eq '^[A-Fa-f0-9]{0,16}$'; then
    echo "Error: SHORT_ID must be hex and at most 16 characters, got: ${SHORT_ID}"
    exit 1
  fi

  if ! printf '%s' "${REALITY_SERVER_NAME}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: REALITY_SERVER_NAME contains invalid characters: ${REALITY_SERVER_NAME}"
    exit 1
  fi

  if ! printf '%s' "${REALITY_DEST}" | grep -Eq '^[A-Za-z0-9._-]+:[0-9]{1,5}$'; then
    echo "Error: REALITY_DEST must look like host:port, got: ${REALITY_DEST}"
    exit 1
  fi

  local dest_port
  dest_port="${REALITY_DEST##*:}"
  if [ "${dest_port}" -lt 1 ] || [ "${dest_port}" -gt 65535 ]; then
    echo "Error: REALITY_DEST port must be 1-65535, got: ${dest_port}"
    exit 1
  fi

  if ! printf '%s' "${FLOW}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: FLOW contains invalid characters: ${FLOW}"
    exit 1
  fi

  if ! printf '%s' "${CLIENT_FINGERPRINT}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: CLIENT_FINGERPRINT contains invalid characters: ${CLIENT_FINGERPRINT}"
    exit 1
  fi

  if ! printf '%s' "${LISTEN_ADDRESS}" | grep -Eq '^[A-Za-z0-9:.%_-]+$'; then
    echo "Error: LISTEN_ADDRESS contains invalid characters: ${LISTEN_ADDRESS}"
    exit 1
  fi
}

write_xray_service() {
  cat > /etc/systemd/system/${XRAY_SERVICE} <<SERVICE_EOF
[Unit]
Description=Xray VLESS Reality terminal service
Documentation=https://xtls.github.io/
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
User=${XRAY_SERVICE_USER}
Group=${XRAY_SERVICE_GROUP}
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${XRAY_CONFIG_DIR} ${INSTALL_DIR}
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

  local TFO_JSON_VALUE="false"
  if is_true "${ENABLE_TFO}"; then
    TFO_JSON_VALUE="true"
  fi

  cat > "${XRAY_CONFIG}" <<CONFIG_EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "listen": "${LISTEN_ADDRESS}",
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
        "sockopt": {
          "tcpFastOpen": ${TFO_JSON_VALUE}
        },
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

  chown root:"${XRAY_SERVICE_GROUP}" "${XRAY_CONFIG}" 2>/dev/null || true
  chmod 640 "${XRAY_CONFIG}"
}

write_clash_config() {
  local TFO_YAML_VALUE="false"
  if is_true "${ENABLE_TFO}"; then
    TFO_YAML_VALUE="true"
  fi

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
    type: vless
    server: "${PUBLIC_IP}"
    port: ${PORT}
    uuid: "${UUID}"
    network: tcp
    udp: true
    tfo: ${TFO_YAML_VALUE}
    tls: true
    servername: "${REALITY_SERVER_NAME}"
    flow: "${FLOW}"
    client-fingerprint: "${CLIENT_FINGERPRINT}"
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"
    skip-cert-verify: false

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

# Generate a Base64-encoded URI list subscription for v2rayN / v2rayNG / Hiddify / Shadowrocket.
# Format: base64( "vless://...\n" )  — one URI per line before encoding.
# When additional protocols (SS, Trojan) are added in the future, append their URIs to the
# here-doc below before encoding. That is the canonical "universal subscription" format.
write_uri_list_sub() {
  # One URI per line before Base64 encoding. The trailing newline after the Base64
  # blob is required by some clients.
  printf '%s\n' "${VLESS_URI}" | base64_one_line > "${VLESS_URI_LIST_FILE}"
  printf '\n' >> "${VLESS_URI_LIST_FILE}"
  chmod 644 "${VLESS_URI_LIST_FILE}"
}
disable_subscription_site_if_disabled() {
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    return 0
  fi

  if [ -L "${NGINX_SITE_LINK}" ] || [ -f "${NGINX_SITE_LINK}" ]; then
    echo "Disabling previous subscription nginx site because ENABLE_SUBSCRIPTION=false (nginx may keep running for other sites)..."
    rm -f "${NGINX_SITE_LINK}"
    if command -v nginx >/dev/null 2>&1; then
      nginx -t && systemctl reload nginx || true
    fi
  fi
}

configure_subscription() {
  SUBSCRIPTION_URL_UNIVERSAL=""
  SUBSCRIPTION_URL_CLASH=""
  SUBSCRIPTION_URL_VLESS=""

  if ! is_true "${ENABLE_SUBSCRIPTION}"; then
    return 0
  fi

  local old_token old_sub_port old_dir
  old_token=""
  old_sub_port=""
  if [ -f "${SUB_ENV_FILE}" ]; then
    old_token="$(load_kv_file_var "${SUB_ENV_FILE}" SUB_TOKEN || true)"
    old_sub_port="$(load_kv_file_var "${SUB_ENV_FILE}" SUB_PORT || true)"
  fi

  if [ -z "${SUB_TOKEN}" ] && ! is_true "${RESET_SUB_TOKEN}"; then
    [ -n "${old_token}" ] && SUB_TOKEN="${old_token}"
    [ -n "${old_sub_port}" ] && SUB_PORT="${old_sub_port}"
  fi

  validate_port_number SUB_PORT "${SUB_PORT}"
  if [ "${SUB_PORT}" = "${PORT}" ]; then
    echo "SUB_PORT must be different from PORT. Current value: ${SUB_PORT}"
    exit 1
  fi

  if ! command -v nginx >/dev/null 2>&1; then
    echo "Error: nginx is not installed. Try rerunning the script, or install nginx manually."
    exit 1
  fi

  SUB_TOKEN="${SUB_TOKEN:-$(openssl rand -hex 24)}"
  if ! validate_subscription_token "${SUB_TOKEN}"; then
    echo "Invalid SUB_TOKEN. Use 24-128 characters: A-Z, a-z, 0-9, underscore, hyphen."
    exit 1
  fi

  SUB_DIR="${SUB_ROOT}/sub/${SUB_TOKEN}"
  SUBSCRIPTION_URL_UNIVERSAL="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}"
  SUBSCRIPTION_URL_CLASH="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}/clash.yaml"
  # Legacy compatibility URL; kept in subscription.env but not highlighted in output.
  SUBSCRIPTION_URL_VLESS="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}/vless"

  # Clean up orphaned token directory from a previous run if the token changed.
  if [ -n "${old_token}" ] && [ "${old_token}" != "${SUB_TOKEN}" ]; then
    if validate_subscription_token "${old_token}"; then
      old_dir="${SUB_ROOT}/sub/${old_token}"
      rm -rf "${old_dir}"
    else
      echo "Warning: old SUB_TOKEN has invalid format; skip old token directory cleanup."
    fi
  fi

  mkdir -p "${SUB_DIR}"

  # clash.yaml — Mihomo / Clash Meta / FlClash / Clash Verge Rev
  cp "${CLASH_FILE}" "${SUB_DIR}/clash.yaml"
  chmod 644 "${SUB_DIR}/clash.yaml"

  # vless — Base64 URI list for v2rayN / v2rayNG / Hiddify / Shadowrocket.
  # This file is also exposed as /sub/TOKEN through nginx rewrite/try_files.
  cp "${VLESS_URI_LIST_FILE}" "${SUB_DIR}/vless"
  chmod 644 "${SUB_DIR}/vless"

  # vless.txt — legacy/browser-friendly path; kept for compatibility, not highlighted in output.
  cp "${VLESS_URI_LIST_FILE}" "${SUB_DIR}/vless.txt"
  chmod 644 "${SUB_DIR}/vless.txt"

  chmod 755 "${SUB_ROOT}" "${SUB_ROOT}/sub" "${SUB_DIR}"

  write_kv_env_file "${SUB_ENV_FILE}" \
    SUB_TOKEN "${SUB_TOKEN}" \
    SUB_PORT "${SUB_PORT}" \
    SUBSCRIPTION_URL_UNIVERSAL "${SUBSCRIPTION_URL_UNIVERSAL}" \
    SUBSCRIPTION_URL_CLASH "${SUBSCRIPTION_URL_CLASH}" \
    SUBSCRIPTION_URL_VLESS "${SUBSCRIPTION_URL_VLESS}"

  cat > "${NGINX_SITE}" <<NGINX_EOF
# This managed site file is overwritten on each run, so the rate-limit zone
# is defined only once inside this nginx include file.
limit_req_zone \$binary_remote_addr zone=cloud_xray_sub_limit:10m rate=${SUB_RATE_LIMIT};

server {
    listen ${SUB_PORT};
    server_name _;

    root ${SUB_ROOT};
    autoindex off;

    # Universal URI-list subscription:
    # /sub/{TOKEN} -> /sub/{TOKEN}/vless
    location ~ ^/sub/[A-Za-z0-9_-]{24,128}$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri/vless =404;
        default_type application/octet-stream;
        add_header Content-Disposition 'attachment; filename="sub.txt"' always;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Clash YAML subscription
    location ~* /clash\.yaml$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri =404;
        default_type text/plain;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Legacy URI-list endpoint kept for compatibility.
    location ~* /vless$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri =404;
        default_type application/octet-stream;
        add_header Content-Disposition 'attachment; filename="vless-sub.txt"' always;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Same URI-list content, easier to open or inspect in a browser.
    location ~* /vless\.txt$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri =404;
        default_type text/plain;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Deny hidden files and anything else not matched above.
    location ~ /\. {
        deny all;
    }

    location / {
        return 404;
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

validate_port_number PORT "${PORT}"
if is_true "${ENABLE_SUBSCRIPTION}"; then
  validate_port_number SUB_PORT "${SUB_PORT}"
fi

if is_true "${ENABLE_SUBSCRIPTION}" && [ "${SUB_PORT}" = "${PORT}" ]; then
  echo "SUB_PORT must be different from PORT. Current value: ${SUB_PORT}"
  exit 1
fi

echo "=========================================="
echo " Xray VLESS Reality Generic Terminal Setup"
echo "=========================================="

echo "[1/11] Installing required packages..."
install_required_packages

echo "[2/11] Applying TCP tuning..."
cat > /etc/sysctl.d/99-cloud-xray-tuning.conf <<SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
  echo "Warning: BBR not activated. Kernel may not support it or provider may restrict it."
fi

echo "[3/11] Preparing directories..."
mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"

echo "[4/11] Detecting public IPv4..."
PUBLIC_IP="$(detect_public_ipv4 || true)"
if [ -z "${PUBLIC_IP}" ]; then
  echo "Failed to detect public IPv4. You can rerun with PUBLIC_IP=x.x.x.x"
  exit 1
fi
echo "Public IPv4: ${PUBLIC_IP}"

echo "Selecting DNS profile for generated client config..."
resolve_dns_profile

echo "[5/11] Stopping old services that may occupy the terminal port..."
systemctl disable --now shadowsocks-libev >/dev/null 2>&1 || true
systemctl disable --now shadowsocks-libev-server@config.service >/dev/null 2>&1 || true
systemctl stop "${XRAY_SERVICE}" >/dev/null 2>&1 || true

echo "[6/11] Installing Xray-core..."
install_xray

echo "[7/11] Loading or generating VLESS/Reality credentials..."
load_or_generate_reality_credentials

echo "[8/11] Checking Reality target..."
check_reality_target

echo "Preparing least-privilege systemd identity..."
ensure_xray_service_identity

echo "[9/11] Writing Xray config and systemd service..."
validate_reality_inputs
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

echo "[10/11] Generating Mihomo/Clash config and VLESS URI-list subscription..."
write_clash_config

URLENCODED_NODE_NAME="$(urlencode "${NODE_NAME}")"
VLESS_URI="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=none&security=reality&sni=${REALITY_SERVER_NAME}&fp=${CLIENT_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=${FLOW}#${URLENCODED_NODE_NAME}"
printf '%s\n' "${VLESS_URI}" > "${VLESS_FILE}"
chmod 644 "${VLESS_FILE}"

# Build URI-list subscription (Base64) — must happen after VLESS_URI is assembled.
write_uri_list_sub

echo "[11/11] Configuring optional HTTP subscription hosting..."
SUBSCRIPTION_URL_UNIVERSAL=""
SUBSCRIPTION_URL_CLASH=""
SUBSCRIPTION_URL_VLESS=""
disable_subscription_site_if_disabled
configure_subscription

cat > "${INFO_FILE}" <<INFO_EOF
Server information:
Node role: Terminal
Server type: Xray VLESS Reality
Server IP: ${PUBLIC_IP}
Port: ${PORT}
Node name: ${NODE_NAME}
Listen address: ${LISTEN_ADDRESS}
Service user: ${XRAY_SERVICE_USER}:${XRAY_SERVICE_GROUP}

DNS profile:
Requested: ${DNS_PROFILE}
Selected: ${DNS_EFFECTIVE_PROFILE}
Server country: ${DNS_DETECTED_COUNTRY}
Auto domestic countries: ${AUTO_DNS_DOMESTIC_COUNTRIES}
Mixed logic: foreign DNS by default; domestic DNS via nameserver-policy for geosite:cn/private

VLESS Reality client:
UUID: ${UUID}
Flow: ${FLOW}
Network: tcp
TCP Fast Open: ${ENABLE_TFO}
Security: reality
SNI / ServerName: ${REALITY_SERVER_NAME}
Fingerprint: ${CLIENT_FINGERPRINT}
Public key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}
Reality dest: ${REALITY_DEST}
Reality target check: ${CHECK_REALITY_TARGET}
Reality check log: ${REALITY_CHECK_LOG}

VLESS link (direct import / troubleshooting):
${VLESS_URI}

Files:
${INFO_FILE}
${CLASH_FILE}
${VLESS_FILE}
${VLESS_URI_LIST_FILE}
${XRAY_CONFIG}
${REALITY_ENV_FILE}
INFO_EOF

if is_true "${ENABLE_SUBSCRIPTION}"; then
  cat >> "${INFO_FILE}" <<INFO_SUB_EOF

Subscription URLs:
  Universal URI-list (v2rayN / v2rayNG / Hiddify / Shadowrocket):
    ${SUBSCRIPTION_URL_UNIVERSAL}
  Mihomo / Clash Meta / FlClash / Clash Verge Rev:
    ${SUBSCRIPTION_URL_CLASH}

Subscription details:
  Port:        ${SUB_PORT}
  Token:       ${SUB_TOKEN}
  Nginx site:  ${NGINX_SITE}
  Rate limit:  ${SUB_RATE_LIMIT}, burst ${SUB_RATE_BURST}

Security warning:
  This subscription is plain HTTP. Use it only on trusted networks.
  Do not share the URL publicly — it contains your full client config.
  Consider restricting TCP ${SUB_PORT} to known source IPs via your cloud firewall.
INFO_SUB_EOF
else
  cat >> "${INFO_FILE}" <<INFO_SUB_EOF

Subscription:
  Enabled: false
  To re-enable: ENABLE_SUBSCRIPTION=true bash terminal_reality.sh
INFO_SUB_EOF
fi

chmod 600 "${INFO_FILE}" "${REALITY_ENV_FILE}"
chown root:"${XRAY_SERVICE_GROUP}" "${XRAY_CONFIG}" 2>/dev/null || true
chmod 640 "${XRAY_CONFIG}"
chmod 644 "${CLASH_FILE}" "${VLESS_FILE}" "${VLESS_URI_LIST_FILE}"

echo ""
echo "=========================================="
echo "Setup complete"
echo "=========================================="
echo "Full server information saved to: ${INFO_FILE}"
echo "VLESS direct import link saved to: ${VLESS_FILE}"

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
if is_true "${ENABLE_SUBSCRIPTION}"; then
  ss -tulnp | grep -E ":(${PORT}|${SUB_PORT})([[:space:]]|$)" || true
else
  ss -tulnp | grep -E ":${PORT}([[:space:]]|$)" || true
fi

echo ""
echo "Important: allow TCP ${PORT} in your cloud firewall/security group."
echo "Reality over TCP does not need UDP ${PORT}."
echo "TCP Fast Open: ${ENABLE_TFO}. Set ENABLE_TFO=false if you encounter compatibility issues."
if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo "Important: allow TCP ${SUB_PORT} if you want to access the subscription URLs from outside."
  echo "Plain HTTP subscription warning: use only on trusted networks, or restrict ${SUB_PORT} by firewall/source IP."
  echo "Do not publish the subscription URLs publicly; they contain your client config."
fi

# Direct import link is saved to ${VLESS_FILE} but is not printed by default.
# Prefer subscription URLs for regular use.
if is_true "${ENABLE_SUBSCRIPTION}"; then
  echo ""
  echo "Subscription URLs:"
  echo "  Universal URI-list (v2rayN / v2rayNG / Hiddify / Shadowrocket):"
  echo "    ${SUBSCRIPTION_URL_UNIVERSAL}"
  echo "  Mihomo / Clash Meta / FlClash / Clash Verge Rev:"
  echo "    ${SUBSCRIPTION_URL_CLASH}"
fi
