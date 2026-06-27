#!/usr/bin/env bash
set -euo pipefail

# RayLink terminal installer.
# Change defaults here or pass values with: sudo env KEY=value bash terminal.sh

ENABLE_SUBSCRIPTION_WAS_SET="${ENABLE_SUBSCRIPTION+x}"

# Operation mode.
HEALTHCHECK_ONLY="${HEALTHCHECK_ONLY:-false}"
for arg in "$@"; do
  case "${arg}" in
    --health-check|--healthcheck|healthcheck)
      HEALTHCHECK_ONLY="true"
      ;;
    *)
      echo "Unknown argument: ${arg}"
      exit 1
      ;;
  esac
done

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

# Generated files.
CLASH_FILE="${INSTALL_DIR}/clash.yaml"
INFO_FILE="${INSTALL_DIR}/server-info.txt"
VLESS_FILE="${INSTALL_DIR}/vless-uri.txt"
VLESS_URI_LIST_FILE="${INSTALL_DIR}/vless-uri-list"
REALITY_ENV_FILE="${INSTALL_DIR}/reality.env"

# Reality endpoint settings. Saved values are reused from REALITY_ENV_FILE unless overridden.
REALITY_DEST="${REALITY_DEST:-}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-}"
CLIENT_FINGERPRINT_POOL="${CLIENT_FINGERPRINT_POOL:-chrome}"
FLOW="${FLOW:-}"

# TCP Fast Open toggle for Xray and generated client config.
ENABLE_TFO="${ENABLE_TFO:-false}"

# DNS profile used when writing the generated Mihomo/Clash YAML.
DNS_PROFILE="${DNS_PROFILE:-mixed}"
AUTO_DNS_DOMESTIC_COUNTRIES="${AUTO_DNS_DOMESTIC_COUNTRIES:-${AUTO_DNS_RETURN_COUNTRIES:-CN}}"
SERVER_COUNTRY="${SERVER_COUNTRY:-}"
DNS_DETECTED_COUNTRY=""
DNS_EFFECTIVE_PROFILE=""

# Basic TLS probe for the selected Reality target.
CHECK_REALITY_TARGET="${CHECK_REALITY_TARGET:-true}"
REALITY_CHECK_STRICT="${REALITY_CHECK_STRICT:-false}"
REALITY_CHECK_LOG="${REALITY_CHECK_LOG:-/tmp/reality_target_check.log}"

# End-to-end local Reality self-test and fallback target selection.
REALITY_SELF_TEST="${REALITY_SELF_TEST:-true}"
REALITY_SELF_TEST_URL="${REALITY_SELF_TEST_URL:-http://example.com}"
REALITY_SELF_TEST_TIMEOUT="${REALITY_SELF_TEST_TIMEOUT:-10}"
REALITY_SELF_TEST_SOCKS_PORT="${REALITY_SELF_TEST_SOCKS_PORT:-10808}"
REALITY_AUTO_FALLBACK="${REALITY_AUTO_FALLBACK:-true}"
# Candidate format: dest|serverName|clientFingerprint, separated by spaces.
REALITY_TARGET_CANDIDATES="${REALITY_TARGET_CANDIDATES:-www.cloudflare.com:443|www.cloudflare.com|chrome www.apple.com:443|www.apple.com|safari addons.mozilla.org:443|addons.mozilla.org|firefox www.speedtest.net:443|www.speedtest.net|chrome www.microsoft.com:443|www.microsoft.com|chrome}"

# HTTP subscription hosting through nginx.
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

# Credential/key reset switch.
RESET_REALITY_CREDENTIALS="${RESET_REALITY_CREDENTIALS:-false}"
UUID="${UUID:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
SHORT_ID="${SHORT_ID:-}"

# Periodic health check timer.
ENABLE_HEALTHCHECK_TIMER="${ENABLE_HEALTHCHECK_TIMER:-true}"
HEALTHCHECK_SCRIPT="${HEALTHCHECK_SCRIPT:-/usr/local/bin/raylink-terminal.sh}"
HEALTHCHECK_SCRIPT_URL="${HEALTHCHECK_SCRIPT_URL:-https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh}"
HEALTHCHECK_ENV_FILE="${HEALTHCHECK_ENV_FILE:-/etc/raylink-terminal-healthcheck.env}"
HEALTHCHECK_ON_CALENDAR="${HEALTHCHECK_ON_CALENDAR:-daily}"
HEALTHCHECK_RANDOMIZED_DELAY="${HEALTHCHECK_RANDOMIZED_DELAY:-30min}"
HEALTHCHECK_SERVICE_NAME="${HEALTHCHECK_SERVICE_NAME:-raylink-terminal-healthcheck.service}"
HEALTHCHECK_TIMER_NAME="${HEALTHCHECK_TIMER_NAME:-raylink-terminal-healthcheck.timer}"

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

  # Reject private, reserved, and non-routable IPv4 ranges.
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

  # Install nginx only when subscription hosting is enabled.
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
  local pool_string="${CLIENT_FINGERPRINT_POOL:-chrome}"
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
    REALITY_DEST="www.cloudflare.com:443"
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

  # Parse key=value files without sourcing them.
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
    # Values are written literally; callers should pass token-like values.
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

  # Never source REALITY_ENV_FILE; read it as plain key=value text.
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

  # Environment variables from this run take priority over saved values.
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

    # Parse both old and new xray x25519 output labels.
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

  # shortId can be empty; generated value is always 16 hex chars.
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
        "network": "raw",
        "security": "reality",
        "sockopt": {
          "tcpFastOpen": ${TFO_JSON_VALUE}
        },
        "realitySettings": {
          "show": false,
          "target": "${REALITY_DEST}",
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


select_free_local_port() {
  local preferred="${1:-10808}"
  local port

  for port in "${preferred}" 10809 18080 28080 38080; do
    if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"; then
      printf '%s\n' "${port}"
      return 0
    fi
  done

  port=$((30000 + RANDOM % 20000))
  printf '%s\n' "${port}"
}

save_reality_env() {
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

run_reality_self_test_once() {
  if ! is_true "${REALITY_SELF_TEST}"; then
    echo "Skip Reality self-test because REALITY_SELF_TEST=false"
    return 0
  fi

  local test_port tmp_cfg tmp_log pid curl_rc
  test_port="$(select_free_local_port "${REALITY_SELF_TEST_SOCKS_PORT}")"
  tmp_cfg="$(mktemp /tmp/raylink-reality-self-test.XXXXXX.json)"
  tmp_log="$(mktemp /tmp/raylink-reality-self-test.XXXXXX.log)"

  cat > "${tmp_cfg}" <<TEST_CONFIG_EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "port": ${test_port},
      "protocol": "socks",
      "settings": {
        "udp": false
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "127.0.0.1",
            "port": ${PORT},
            "users": [
              {
                "id": "${UUID}",
                "encryption": "none",
                "flow": "${FLOW}"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "serverName": "${REALITY_SERVER_NAME}",
          "fingerprint": "${CLIENT_FINGERPRINT}",
          "password": "${PUBLIC_KEY}",
          "shortId": "${SHORT_ID}",
          "spiderX": "/"
        }
      }
    }
  ]
}
TEST_CONFIG_EOF

  "${XRAY_BIN}" run -config "${tmp_cfg}" >"${tmp_log}" 2>&1 &
  pid="$!"
  sleep 1

  curl_rc=1
  if kill -0 "${pid}" >/dev/null 2>&1; then
    if timeout "$((REALITY_SELF_TEST_TIMEOUT + 5))" \
      curl -fsS -x "socks5h://127.0.0.1:${test_port}" \
      -I --connect-timeout "${REALITY_SELF_TEST_TIMEOUT}" \
      "${REALITY_SELF_TEST_URL}" >/dev/null 2>&1; then
      curl_rc=0
    fi
  fi

  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true

  if [ "${curl_rc}" -eq 0 ]; then
    rm -f "${tmp_cfg}" "${tmp_log}"
    return 0
  fi

  echo "Reality self-test failed for ${REALITY_SERVER_NAME} (${REALITY_DEST}) with fingerprint=${CLIENT_FINGERPRINT}."
  echo "Self-test client log tail:"
  tail -n 30 "${tmp_log}" || true
  rm -f "${tmp_cfg}" "${tmp_log}"
  return 1
}

apply_reality_candidate() {
  local candidate="$1"
  local cand_dest cand_sni cand_fp rest

  cand_dest="${candidate%%|*}"
  rest="${candidate#*|}"
  if [ "${rest}" = "${candidate}" ]; then
    echo "Warning: skip invalid Reality candidate: ${candidate}"
    return 1
  fi

  cand_sni="${rest%%|*}"
  if [ "${cand_sni}" = "${rest}" ]; then
    echo "Warning: skip incomplete Reality candidate: ${candidate}"
    return 1
  fi
  cand_fp="${rest#*|}"

  if [ -z "${cand_dest}" ] || [ -z "${cand_sni}" ] || [ -z "${cand_fp}" ]; then
    echo "Warning: skip incomplete Reality candidate: ${candidate}"
    return 1
  fi

  case "${cand_fp}" in
    chrome|firefox|safari|edge|ios|android|random) ;;
    *)
      echo "Warning: skip candidate with invalid fingerprint '${cand_fp}': ${candidate}"
      return 1
      ;;
  esac

  REALITY_DEST="${cand_dest}"
  REALITY_SERVER_NAME="${cand_sni}"
  CLIENT_FINGERPRINT="${cand_fp}"
  normalize_reality_target
}

restart_xray_with_current_reality_target() {
  validate_reality_inputs
  write_xray_config
  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG}"
  systemctl restart "${XRAY_SERVICE}"
  sleep 1

  if ! systemctl is-active --quiet "${XRAY_SERVICE}"; then
    echo "Xray failed to start after changing Reality target."
    systemctl status "${XRAY_SERVICE}" --no-pager || true
    journalctl -u "${XRAY_SERVICE}" -n 80 --no-pager || true
    return 1
  fi

  return 0
}

perform_reality_self_test_with_fallbacks() {
  if ! is_true "${REALITY_SELF_TEST}"; then
    echo "Skip Reality self-test because REALITY_SELF_TEST=false"
    return 0
  fi

  echo "Running end-to-end Reality self-test: ${REALITY_SELF_TEST_URL}"
  if run_reality_self_test_once; then
    echo "Reality self-test passed with target: ${REALITY_SERVER_NAME} (${REALITY_DEST})"
    save_reality_env
    return 0
  fi

  if ! is_true "${REALITY_AUTO_FALLBACK}"; then
    echo "Reality self-test failed and REALITY_AUTO_FALLBACK=false."
    exit 1
  fi

  echo "Trying fallback Reality targets (this may take up to about 60 seconds if several candidates fail)..."

  local original_dest original_sni original_fp candidate candidate_dest
  original_dest="${REALITY_DEST}"
  original_sni="${REALITY_SERVER_NAME}"
  original_fp="${CLIENT_FINGERPRINT}"

  for candidate in ${REALITY_TARGET_CANDIDATES}; do
    candidate_dest="${candidate%%|*}"
    if [ "${candidate_dest}" = "${original_dest}" ]; then
      continue
    fi

    echo "Trying Reality target candidate: ${candidate}"
    if ! apply_reality_candidate "${candidate}"; then
      continue
    fi

    check_reality_target
    if restart_xray_with_current_reality_target && run_reality_self_test_once; then
      echo "Selected working Reality target: ${REALITY_SERVER_NAME} (${REALITY_DEST}), fingerprint=${CLIENT_FINGERPRINT}"
      save_reality_env
      return 0
    fi
  done

  REALITY_DEST="${original_dest}"
  REALITY_SERVER_NAME="${original_sni}"
  CLIENT_FINGERPRINT="${original_fp}"
  echo "Error: all Reality target candidates failed the end-to-end self-test."
  echo "Restoring the original Reality target and keeping the existing client configuration."
  restart_xray_with_current_reality_target || true
  echo "Try setting REALITY_DEST / REALITY_SERVER_NAME / CLIENT_FINGERPRINT manually."
  exit 1
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

write_uri_list_sub() {
  # Trailing newline required by some subscription clients.
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
  # Legacy alias kept in subscription.env.
  SUBSCRIPTION_URL_VLESS="http://${PUBLIC_IP}:${SUB_PORT}/sub/${SUB_TOKEN}/vless"

  # Remove the old token directory when the token changes.
  if [ -n "${old_token}" ] && [ "${old_token}" != "${SUB_TOKEN}" ]; then
    if validate_subscription_token "${old_token}"; then
      old_dir="${SUB_ROOT}/sub/${old_token}"
      rm -rf "${old_dir}"
    else
      echo "Warning: old SUB_TOKEN has invalid format; skip old token directory cleanup."
    fi
  fi

  mkdir -p "${SUB_DIR}"

  # Mihomo/Clash subscription file.
  cp "${CLASH_FILE}" "${SUB_DIR}/clash.yaml"
  chmod 644 "${SUB_DIR}/clash.yaml"

  # Universal URI-list endpoint.
  cp "${VLESS_URI_LIST_FILE}" "${SUB_DIR}/vless"
  chmod 644 "${SUB_DIR}/vless"

  # Plain-text compatible alias.
  cp "${VLESS_URI_LIST_FILE}" "${SUB_DIR}/vless.txt"
  chmod 644 "${SUB_DIR}/vless.txt"

  chmod 755 "${SUB_ROOT}" "${SUB_ROOT}/sub" "${SUB_DIR}"

  write_kv_env_file "${SUB_ENV_FILE}" \
    SUB_TOKEN "${SUB_TOKEN}" \
    SUB_PORT "${SUB_PORT}" \
    SUBSCRIPTION_URL_UNIVERSAL "${SUBSCRIPTION_URL_UNIVERSAL}" \
    SUBSCRIPTION_URL_CLASH "${SUBSCRIPTION_URL_CLASH}" \
    SUBSCRIPTION_URL_VLESS "${SUBSCRIPTION_URL_VLESS}"

  local tmp_nginx_site nginx_site_changed nginx_link_changed
  tmp_nginx_site="$(mktemp /tmp/raylink-nginx-site.XXXXXX)"
  nginx_site_changed=false
  nginx_link_changed=false

  cat > "${tmp_nginx_site}" <<NGINX_EOF
# Managed nginx site; overwritten only when content changes.
limit_req_zone \$binary_remote_addr zone=cloud_xray_sub_limit:10m rate=${SUB_RATE_LIMIT};

server {
    listen ${SUB_PORT};
    server_name _;

    root ${SUB_ROOT};
    autoindex off;

    # /sub/{TOKEN} -> /sub/{TOKEN}/vless
    location ~ "^/sub/[A-Za-z0-9_-]{24,128}$" {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri/vless =404;
        default_type application/octet-stream;
        add_header Content-Disposition 'attachment; filename="sub.txt"' always;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Clash YAML endpoint.
    location ~* /clash\.yaml$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri =404;
        default_type text/plain;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Legacy URI-list endpoint.
    location ~* /vless$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri =404;
        default_type application/octet-stream;
        add_header Content-Disposition 'attachment; filename="vless-sub.txt"' always;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Browser-readable URI-list alias.
    location ~* /vless\.txt$ {
        limit_req zone=cloud_xray_sub_limit burst=${SUB_RATE_BURST} nodelay;
        try_files \$uri =404;
        default_type text/plain;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-store" always;
    }

    # Block hidden files.
    location ~ /\. {
        deny all;
    }

    location / {
        return 404;
    }
}
NGINX_EOF

  if [ ! -f "${NGINX_SITE}" ] || ! cmp -s "${tmp_nginx_site}" "${NGINX_SITE}"; then
    install -m 644 "${tmp_nginx_site}" "${NGINX_SITE}"
    nginx_site_changed=true
  fi
  rm -f "${tmp_nginx_site}"

  if [ "$(readlink -f "${NGINX_SITE_LINK}" 2>/dev/null || true)" != "$(readlink -f "${NGINX_SITE}" 2>/dev/null || true)" ]; then
    ln -sf "${NGINX_SITE}" "${NGINX_SITE_LINK}"
    nginx_link_changed=true
  fi

  systemctl enable nginx >/dev/null 2>&1 || true
  if [ "${nginx_site_changed}" = "true" ] || [ "${nginx_link_changed}" = "true" ] || ! systemctl is-active --quiet nginx; then
    nginx -t
    if systemctl is-active --quiet nginx; then
      systemctl reload nginx
    else
      systemctl start nginx
    fi
  else
    echo "nginx subscription site unchanged; skip reload."
  fi
}
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root, for example:"
    echo "sudo env PORT=${PORT} NODE_NAME=${NODE_NAME} bash terminal.sh"
    exit 1
  fi
}

validate_common_ports() {
  validate_port_number PORT "${PORT}"
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    validate_port_number SUB_PORT "${SUB_PORT}"
  fi

  if is_true "${ENABLE_SUBSCRIPTION}" && [ "${SUB_PORT}" = "${PORT}" ]; then
    echo "SUB_PORT must be different from PORT. Current value: ${SUB_PORT}"
    exit 1
  fi
}

apply_tcp_tuning() {
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
}

detect_public_ip_and_resolve_dns() {
  PUBLIC_IP="$(detect_public_ipv4 || true)"
  if [ -z "${PUBLIC_IP}" ]; then
    echo "Failed to detect public IPv4. You can rerun with PUBLIC_IP=x.x.x.x"
    exit 1
  fi
  echo "Public IPv4: ${PUBLIC_IP}"

  resolve_dns_profile
}

load_existing_reality_credentials_for_healthcheck() {
  if [ ! -f "${REALITY_ENV_FILE}" ]; then
    echo "Error: ${REALITY_ENV_FILE} does not exist. Run the full installer first."
    exit 1
  fi

  UUID="${UUID:-$(load_kv_file_var "${REALITY_ENV_FILE}" UUID)}"
  PRIVATE_KEY="${PRIVATE_KEY:-$(load_kv_file_var "${REALITY_ENV_FILE}" PRIVATE_KEY)}"
  PUBLIC_KEY="${PUBLIC_KEY:-$(load_kv_file_var "${REALITY_ENV_FILE}" PUBLIC_KEY)}"
  SHORT_ID="${SHORT_ID:-$(load_kv_file_var "${REALITY_ENV_FILE}" SHORT_ID)}"
  REALITY_DEST="${REALITY_DEST:-$(load_kv_file_var "${REALITY_ENV_FILE}" REALITY_DEST)}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-$(load_kv_file_var "${REALITY_ENV_FILE}" REALITY_SERVER_NAME)}"
  CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-$(load_kv_file_var "${REALITY_ENV_FILE}" CLIENT_FINGERPRINT)}"
  FLOW="${FLOW:-$(load_kv_file_var "${REALITY_ENV_FILE}" FLOW)}"

  FLOW="${FLOW:-xtls-rprx-vision}"
  normalize_reality_target

  if [ -z "${UUID}" ] || [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ] || [ -z "${CLIENT_FINGERPRINT}" ]; then
    echo "Error: saved Reality credentials are incomplete in ${REALITY_ENV_FILE}."
    exit 1
  fi
}

assemble_vless_uri() {
  URLENCODED_NODE_NAME="$(urlencode "${NODE_NAME}")"
  VLESS_URI="vless://${UUID}@${PUBLIC_IP}:${PORT}?encryption=none&security=reality&sni=${REALITY_SERVER_NAME}&fp=${CLIENT_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=${FLOW}#${URLENCODED_NODE_NAME}"
  printf '%s\n' "${VLESS_URI}" > "${VLESS_FILE}"
  chmod 644 "${VLESS_FILE}"
}

write_info_file() {
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
Reality self-test: ${REALITY_SELF_TEST}
Reality auto fallback: ${REALITY_AUTO_FALLBACK}
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
  To re-enable: ENABLE_SUBSCRIPTION=true bash terminal.sh
INFO_SUB_EOF
  fi

  chmod 600 "${INFO_FILE}" "${REALITY_ENV_FILE}"
  chown root:"${XRAY_SERVICE_GROUP}" "${XRAY_CONFIG}" 2>/dev/null || true
  chmod 640 "${XRAY_CONFIG}"
  chmod 644 "${CLASH_FILE}" "${VLESS_FILE}" "${VLESS_URI_LIST_FILE}"
}

sync_client_outputs() {
  write_clash_config
  assemble_vless_uri
  write_uri_list_sub

  SUBSCRIPTION_URL_UNIVERSAL=""
  SUBSCRIPTION_URL_CLASH=""
  SUBSCRIPTION_URL_VLESS=""
  disable_subscription_site_if_disabled
  configure_subscription
  write_info_file
}

ensure_xray_running_for_healthcheck() {
  if [ -f "${XRAY_CONFIG}" ] && systemctl is-active --quiet "${XRAY_SERVICE}"; then
    return 0
  fi

  echo "Xray is not active or config is missing; restoring service from saved state."
  ensure_xray_service_identity
  write_xray_service
  systemctl daemon-reload
  restart_xray_with_current_reality_target
  systemctl enable "${XRAY_SERVICE}" >/dev/null 2>&1 || true
}

write_healthcheck_env_file() {
  # Keep fallback candidates in the script defaults unless explicitly set at runtime.
  # Persisting the list here would freeze old candidates after script updates.
  write_kv_env_file "${HEALTHCHECK_ENV_FILE}" \
    PORT "${PORT}" \
    NODE_NAME "${NODE_NAME}" \
    INSTALL_DIR "${INSTALL_DIR}" \
    XRAY_BIN "${XRAY_BIN}" \
    XRAY_CONFIG_DIR "${XRAY_CONFIG_DIR}" \
    XRAY_CONFIG "${XRAY_CONFIG}" \
    XRAY_SHARE_DIR "${XRAY_SHARE_DIR}" \
    XRAY_SERVICE_USER "${XRAY_SERVICE_USER}" \
    XRAY_SERVICE_GROUP "${XRAY_SERVICE_GROUP}" \
    LISTEN_ADDRESS "${LISTEN_ADDRESS}" \
    ENABLE_TFO "${ENABLE_TFO}" \
    DNS_PROFILE "${DNS_PROFILE}" \
    AUTO_DNS_DOMESTIC_COUNTRIES "${AUTO_DNS_DOMESTIC_COUNTRIES}" \
    SERVER_COUNTRY "${SERVER_COUNTRY}" \
    CHECK_REALITY_TARGET "${CHECK_REALITY_TARGET}" \
    REALITY_CHECK_STRICT "${REALITY_CHECK_STRICT}" \
    REALITY_SELF_TEST "${REALITY_SELF_TEST}" \
    REALITY_SELF_TEST_URL "${REALITY_SELF_TEST_URL}" \
    REALITY_SELF_TEST_TIMEOUT "${REALITY_SELF_TEST_TIMEOUT}" \
    REALITY_SELF_TEST_SOCKS_PORT "${REALITY_SELF_TEST_SOCKS_PORT}" \
    REALITY_AUTO_FALLBACK "${REALITY_AUTO_FALLBACK}" \
    ENABLE_SUBSCRIPTION "${ENABLE_SUBSCRIPTION}" \
    SUB_PORT "${SUB_PORT}" \
    SUB_ROOT "${SUB_ROOT}" \
    SUB_ENV_FILE "${SUB_ENV_FILE}" \
    NGINX_SITE "${NGINX_SITE}" \
    NGINX_SITE_LINK "${NGINX_SITE_LINK}" \
    SUB_RATE_LIMIT "${SUB_RATE_LIMIT}" \
    SUB_RATE_BURST "${SUB_RATE_BURST}"
}

install_healthcheck_timer() {
  if ! is_true "${ENABLE_HEALTHCHECK_TIMER}"; then
    echo "Skip health check timer because ENABLE_HEALTHCHECK_TIMER=false"
    return 0
  fi

  local script_dir src_path
  script_dir="$(dirname "${HEALTHCHECK_SCRIPT}")"
  mkdir -p "${script_dir}"

  src_path="${BASH_SOURCE[0]:-}"
  if [ -n "${src_path}" ] && [ -f "${src_path}" ] && [ -r "${src_path}" ]; then
    if [ "$(readlink -f "${src_path}")" != "$(readlink -f "${HEALTHCHECK_SCRIPT}" 2>/dev/null || printf '%s' "${HEALTHCHECK_SCRIPT}")" ]; then
      cp "${src_path}" "${HEALTHCHECK_SCRIPT}"
    fi
  else
    if ! curl -fsSL "${HEALTHCHECK_SCRIPT_URL}" -o "${HEALTHCHECK_SCRIPT}"; then
      echo "Warning: failed to install local health check script from ${HEALTHCHECK_SCRIPT_URL}."
      echo "The terminal node is installed, but the periodic health check timer was not enabled."
      return 0
    fi
  fi
  chmod 755 "${HEALTHCHECK_SCRIPT}"
  write_healthcheck_env_file

  cat > "/etc/systemd/system/${HEALTHCHECK_SERVICE_NAME}" <<SERVICE_EOF
[Unit]
Description=RayLink terminal Reality health check
After=network-online.target ${XRAY_SERVICE}
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-${HEALTHCHECK_ENV_FILE}
ExecStart=${HEALTHCHECK_SCRIPT} --health-check
SERVICE_EOF

  cat > "/etc/systemd/system/${HEALTHCHECK_TIMER_NAME}" <<TIMER_EOF
[Unit]
Description=Run RayLink terminal Reality health check periodically

[Timer]
OnCalendar=${HEALTHCHECK_ON_CALENDAR}
RandomizedDelaySec=${HEALTHCHECK_RANDOMIZED_DELAY}
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

  systemctl daemon-reload
  systemctl enable --now "${HEALTHCHECK_TIMER_NAME}" >/dev/null 2>&1 || true
  echo "Health check timer enabled: ${HEALTHCHECK_TIMER_NAME} (${HEALTHCHECK_ON_CALENDAR}, randomized delay ${HEALTHCHECK_RANDOMIZED_DELAY})"
}

run_healthcheck_mode() {
  require_root

  if [ -z "${ENABLE_SUBSCRIPTION_WAS_SET}" ] && [ ! -f "${SUB_ENV_FILE}" ]; then
    ENABLE_SUBSCRIPTION="false"
  fi

  validate_common_ports

  echo "=========================================="
  echo " RayLink terminal health check"
  echo "=========================================="

  if [ ! -x "${XRAY_BIN}" ]; then
    echo "Error: Xray binary not found at ${XRAY_BIN}. Run the full installer first."
    exit 1
  fi

  mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"
  detect_public_ip_and_resolve_dns
  load_existing_reality_credentials_for_healthcheck
  validate_reality_inputs
  ensure_xray_running_for_healthcheck

  perform_reality_self_test_with_fallbacks
  sync_client_outputs

  echo "Health check complete. Client files and subscription data are up to date."
  echo "Current public IPv4: ${PUBLIC_IP}"
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Subscription URL: ${SUBSCRIPTION_URL_CLASH}"
  fi
}

run_full_install() {
  require_root
  validate_common_ports

  echo "=========================================="
  echo " Xray VLESS Reality Generic Terminal Setup"
  echo "=========================================="

  echo "[1/12] Installing required packages..."
  install_required_packages

  echo "[2/12] Applying TCP tuning..."
  apply_tcp_tuning

  echo "[3/12] Preparing directories..."
  mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"

  echo "[4/12] Detecting public IPv4 and selecting DNS profile..."
  detect_public_ip_and_resolve_dns

  echo "[5/12] Stopping old services that may occupy the terminal port..."
  systemctl disable --now shadowsocks-libev >/dev/null 2>&1 || true
  systemctl disable --now shadowsocks-libev-server@config.service >/dev/null 2>&1 || true
  systemctl stop "${XRAY_SERVICE}" >/dev/null 2>&1 || true

  echo "[6/12] Installing Xray-core..."
  install_xray

  echo "[7/12] Loading or generating VLESS/Reality credentials..."
  load_or_generate_reality_credentials

  echo "[8/12] Checking Reality target..."
  check_reality_target

  echo "[9/12] Writing Xray config and systemd service..."
  ensure_xray_service_identity
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

  echo "[10/12] Running Reality self-test and fallback target selection..."
  perform_reality_self_test_with_fallbacks

  echo "[11/12] Generating Mihomo/Clash config and VLESS URI-list subscription..."
  sync_client_outputs

  echo "[12/12] Configuring periodic health check..."
  install_healthcheck_timer

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
  echo "TCP Fast Open: ${ENABLE_TFO}. Set ENABLE_TFO=true if your client and network path support it."
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Important: allow TCP ${SUB_PORT} if you want to access the subscription URLs from outside."
    echo "Plain HTTP subscription warning: use only on trusted networks, or restrict ${SUB_PORT} by firewall/source IP."
    echo "Do not publish the subscription URLs publicly; they contain your client config."
  fi
  if is_true "${ENABLE_HEALTHCHECK_TIMER}"; then
    echo "Health check timer: ${HEALTHCHECK_TIMER_NAME}"
  fi
}

if is_true "${HEALTHCHECK_ONLY}"; then
  run_healthcheck_mode
else
  run_full_install
fi
