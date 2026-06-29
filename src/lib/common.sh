#!/usr/bin/env bash
# RayLink shared helpers. Sourced by the raylink dispatcher.
# Generic, role-agnostic functions reused by terminal and (future) relay.

is_true() {
  case "${1:-}" in
    true|TRUE|yes|YES|1|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this command as root, for example:"
    echo "  sudo raylink ${RAYLINK_COMMAND:-terminal}"
    exit 1
  fi
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

valid_public_ipv6() {
  local ip="${1:-}"
  local colons
  ip="${ip%%%*}"                                    # strip a %zone-id suffix
  ip="$(printf '%s' "${ip}" | tr 'A-F' 'a-f')"
  # Only hex digits and colons.
  printf '%s' "${ip}" | grep -Eq '^[0-9a-f:]+$' || return 1
  # No group may exceed 4 hex digits.
  printf '%s' "${ip}" | grep -Eq '[0-9a-f]{5,}' && return 1
  # Structural sanity: a '::' compressed form (2-7 colons) or a full 8-group
  # form (exactly 7 colons). This rejects junk like "abc:def".
  colons="$(printf '%s' "${ip}" | tr -cd ':' | wc -c | tr -d ' ')"
  if printf '%s' "${ip}" | grep -q '::'; then
    { [ "${colons}" -ge 2 ] && [ "${colons}" -le 7 ]; } || return 1
  else
    [ "${colons}" -eq 7 ] || return 1
  fi
  # Reject non-global ranges (loopback, unspecified, link-local, ULA, multicast,
  # documentation, IPv4-mapped, NAT64 well-known prefix).
  case "${ip}" in
    ::1|::) return 1 ;;
    fe8*|fe9*|fea*|feb*) return 1 ;;                # fe80::/10 link-local
    fc*|fd*) return 1 ;;                            # fc00::/7 unique local
    ff*) return 1 ;;                                # ff00::/8 multicast
    2001:db8:*|2001:0db8:*) return 1 ;;            # 2001:db8::/32 documentation
    ::ffff:*) return 1 ;;                           # ::ffff:0:0/96 IPv4-mapped
    64:ff9b:*) return 1 ;;                          # 64:ff9b::/96 NAT64
  esac
  return 0
}

# Detect a public IPv6 address (pure detector; the PUBLIC_IP override is
# handled by the orchestrator).
detect_public_ipv6() {
  local url ip
  for url in \
    "https://api6.ipify.org" \
    "https://ipv6.icanhazip.com" \
    "https://v6.ident.me" \
    "https://ipv6.ip.sb"; do
    ip="$(curl -6 -fsS -m 6 "${url}" 2>/dev/null | tr -d ' \r\n\t' | head -c 64 || true)"
    if valid_public_ipv6 "${ip}"; then
      printf '%s\n' "${ip}"
      return 0
    fi
  done

  return 1
}

# Bracket an IPv6 literal for use in a URI/URL authority; leave IPv4 and
# hostnames untouched. e.g. 2001:db8::1 -> [2001:db8::1]; 1.2.3.4 -> 1.2.3.4
format_host_for_uri() {
  local host="${1:-}"
  case "${host}" in
    \[*\]) printf '%s' "${host}" ;;                # already bracketed
    *:*)   printf '[%s]' "${host}" ;;              # contains ':' -> IPv6
    *)     printf '%s' "${host}" ;;
  esac
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

base64_one_line() {
  if printf '' | base64 -w 0 >/dev/null 2>&1; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
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
    # Strip newlines (line-based env files cannot represent them) and escape
    # embedded single quotes using the POSIX '\'' idiom so the single-quoted
    # value stays valid for shell `source`, systemd EnvironmentFile, and the
    # load_kv_file_var reader. e.g. NODE_NAME="Bob's node" -> NODE_NAME='Bob'\''s node'
    value="${value//$'\n'/ }"
    local escaped=${value//\'/\'\\\'\'}
    printf "%s='%s'\n" "${key}" "${escaped}" >> "${file}"
  done
  chmod 600 "${file}"
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

# Validate the node port and (when subscription is enabled) the subscription
# port. Shared by the terminal and relay commands.
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

# render_template TEMPLATE_PATH VAR1 VAR2 ...
#
# Substitutes only the explicitly listed ${VAR} placeholders using envsubst.
# A whitelist is mandatory so that literal shell-style tokens in the template
# (e.g. nginx variables like $binary_remote_addr) are preserved untouched.
render_template() {
  local template="$1"
  shift

  if [ ! -f "${template}" ]; then
    echo "Error: template not found: ${template}" >&2
    exit 1
  fi
  if ! command -v envsubst >/dev/null 2>&1; then
    echo "Error: envsubst not found (install gettext-base)." >&2
    exit 1
  fi

  local whitelist="" name
  for name in "$@"; do
    # Export so envsubst can see the value; config values are not secrets
    # beyond what already lives in the environment.
    export "${name?}"
    whitelist+="\${${name}} "
  done

  envsubst "${whitelist}" < "${template}"
}

# Prepend an optional proxy/mirror prefix to a URL (empty prefix = unchanged).
apply_url_prefix() {
  local prefix="${1:-}" url="${2:-}"
  if [ -n "${prefix}" ]; then printf '%s%s' "${prefix}" "${url}"; else printf '%s' "${url}"; fi
}

# curl wrapper with retry, timeouts, and stall detection. Tunable via env:
# DOWNLOAD_RETRY, DOWNLOAD_RETRY_DELAY, CONNECT_TIMEOUT, MAX_TIME, SPEED_TIME, SPEED_LIMIT.
fetch_file() {
  local url="$1" output="$2"
  local -a opts=(
    -fL
    --retry "${DOWNLOAD_RETRY:-3}"
    --retry-delay "${DOWNLOAD_RETRY_DELAY:-2}"
    --connect-timeout "${CONNECT_TIMEOUT:-15}"
    --max-time "${MAX_TIME:-180}"
    --speed-time "${SPEED_TIME:-30}"
    --speed-limit "${SPEED_LIMIT:-1}"
  )
  # --retry-all-errors needs a newer curl (>= 7.71); add it only if supported.
  if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
    opts+=(--retry-all-errors)
  fi
  curl "${opts[@]}" "${url}" -o "${output}"
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
  command -v envsubst >/dev/null 2>&1 || packages+=(gettext-base)
  command -v getent >/dev/null 2>&1 || packages+=(passwd)
  command -v useradd >/dev/null 2>&1 || packages+=(passwd)
  command -v groupadd >/dev/null 2>&1 || packages+=(passwd)

  # Install nginx only when subscription hosting is enabled.
  if is_true "${ENABLE_SUBSCRIPTION:-false}"; then
    command -v nginx >/dev/null 2>&1 || packages+=(nginx)
  fi

  apt update
  apt install -y "${packages[@]}"
}

apply_tcp_tuning() {
  cat > /etc/sysctl.d/99-cloud-xray-tuning.conf <<'SYSCTL_EOF'
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

# (end of common.sh)
