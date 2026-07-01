#!/usr/bin/env bash
# Relay upstream: the parameters the relay uses to connect to the exit node.
#
# These live ONLY on the relay server (UPSTREAM_ENV_FILE) and are never exposed
# in the relay's client subscription. Inputs are accepted three ways, in
# priority order: explicit UPSTREAM_* fields, UPSTREAM_VLESS_URI, or
# UPSTREAM_SUBSCRIPTION_URL (which can also be refreshed by the health check).

# Parse an exit VLESS URI into UPSTREAM_* variables.
#   vless://UUID@HOST:PORT?encryption=none&security=reality&sni=..&fp=..&pbk=..&sid=..&type=tcp&flow=..#name
parse_upstream_vless_uri() {
  local uri="${1:-}"
  if [ -z "${uri}" ]; then
    echo "Error: empty upstream VLESS URI." >&2
    return 1
  fi
  if [ "${uri#vless://}" = "${uri}" ]; then
    echo "Error: upstream URI must start with vless:// : ${uri:0:16}..." >&2
    return 1
  fi

  local body userinfo rest hostport query
  body="${uri#vless://}"
  body="${body%%#*}"          # drop #fragment (node name)

  userinfo="${body%%@*}"      # UUID
  rest="${body#*@}"           # HOST:PORT?query
  hostport="${rest%%\?*}"     # HOST:PORT
  query=""
  if [ "${rest}" != "${hostport}" ]; then
    query="${rest#*\?}"
  fi

  UPSTREAM_UUID="${userinfo}"
  UPSTREAM_ADDRESS="${hostport%%:*}"
  if [ "${hostport#*:}" != "${hostport}" ]; then
    UPSTREAM_PORT="${hostport##*:}"
  else
    UPSTREAM_PORT="${UPSTREAM_PORT:-443}"
  fi

  local pair key value old_ifs
  old_ifs="${IFS}"
  IFS='&'
  for pair in ${query}; do
    key="${pair%%=*}"
    value="${pair#*=}"
    case "${key}" in
      sni)  UPSTREAM_SERVER_NAME="${value}" ;;
      fp)   UPSTREAM_FINGERPRINT="${value}" ;;
      pbk)  UPSTREAM_PUBLIC_KEY="${value}" ;;
      sid)  UPSTREAM_SHORT_ID="${value}" ;;
      flow) UPSTREAM_FLOW="${value}" ;;
      *) : ;;
    esac
  done
  IFS="${old_ifs}"
}

# Fetch the exit subscription and parse the first VLESS URI it contains.
# The exit /vless endpoint returns a base64-encoded URI list; plain text is
# also tolerated. Sets UPSTREAM_CHANGED=true when the effective target differs.
refresh_upstream_from_subscription() {
  local url="${1:-${UPSTREAM_SUBSCRIPTION_URL:-}}"
  if [ -z "${url}" ]; then
    echo "Error: no UPSTREAM_SUBSCRIPTION_URL to refresh from." >&2
    return 1
  fi

  local raw decoded content first_uri
  raw="$(curl -fsSL -m 15 "${url}" 2>/dev/null || true)"
  if [ -z "${raw}" ]; then
    echo "Warning: failed to fetch upstream subscription: ${url}" >&2
    return 1
  fi

  # Try base64 decode; fall back to the raw payload if it is already plain text.
  decoded="$(printf '%s' "${raw}" | base64 -d 2>/dev/null || true)"
  if printf '%s' "${decoded}" | grep -q 'vless://'; then
    content="${decoded}"
  else
    content="${raw}"
  fi

  first_uri="$(printf '%s\n' "${content}" | grep -m1 '^vless://' || true)"
  if [ -z "${first_uri}" ]; then
    echo "Warning: upstream subscription contained no VLESS URI: ${url}" >&2
    return 1
  fi

  local before
  before="${UPSTREAM_ADDRESS:-}|${UPSTREAM_PORT:-}|${UPSTREAM_UUID:-}|${UPSTREAM_PUBLIC_KEY:-}|${UPSTREAM_SERVER_NAME:-}|${UPSTREAM_SHORT_ID:-}|${UPSTREAM_FLOW:-}"
  parse_upstream_vless_uri "${first_uri}" || return 1
  local after
  after="${UPSTREAM_ADDRESS:-}|${UPSTREAM_PORT:-}|${UPSTREAM_UUID:-}|${UPSTREAM_PUBLIC_KEY:-}|${UPSTREAM_SERVER_NAME:-}|${UPSTREAM_SHORT_ID:-}|${UPSTREAM_FLOW:-}"

  if [ "${before}" != "${after}" ]; then
    UPSTREAM_CHANGED="true"
    echo "Upstream parameters updated from subscription."
  else
    echo "Upstream parameters unchanged after subscription refresh."
  fi
}

# True if the user supplied an upstream source on THIS run (env vars).
has_upstream_input() {
  [ -n "${UPSTREAM_VLESS_URI:-}" ] || [ -n "${UPSTREAM_SUBSCRIPTION_URL:-}" ] || [ -n "${UPSTREAM_ADDRESS:-}" ]
}

# True if a complete upstream is already saved on disk from a previous run.
has_saved_upstream_config() {
  [ -f "${UPSTREAM_ENV_FILE}" ] || return 1
  [ -n "$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_ADDRESS)" ] \
    && [ -n "$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_UUID)" ] \
    && [ -n "$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_PUBLIC_KEY)" ]
}

print_missing_upstream_help() {
  echo "A relay requires upstream exit parameters. Provide one of:" >&2
  echo "  UPSTREAM_SUBSCRIPTION_URL=http://EXIT_IP:8080/sub/TOKEN   (recommended)" >&2
  echo "  UPSTREAM_VLESS_URI='vless://...'                              (exit link)" >&2
  echo "  UPSTREAM_ADDRESS=.. UPSTREAM_UUID=.. UPSTREAM_PUBLIC_KEY=..   (individual fields)" >&2
  echo "See docs/relay.md." >&2
}

_load_saved_upstream() {
  [ -f "${UPSTREAM_ENV_FILE}" ] || return 0
  UPSTREAM_ADDRESS="${UPSTREAM_ADDRESS:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_ADDRESS)}"
  UPSTREAM_PORT="${UPSTREAM_PORT:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_PORT)}"
  UPSTREAM_UUID="${UPSTREAM_UUID:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_UUID)}"
  UPSTREAM_FLOW="${UPSTREAM_FLOW:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_FLOW)}"
  UPSTREAM_SERVER_NAME="${UPSTREAM_SERVER_NAME:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_SERVER_NAME)}"
  UPSTREAM_FINGERPRINT="${UPSTREAM_FINGERPRINT:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_FINGERPRINT)}"
  UPSTREAM_PUBLIC_KEY="${UPSTREAM_PUBLIC_KEY:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_PUBLIC_KEY)}"
  UPSTREAM_SHORT_ID="${UPSTREAM_SHORT_ID:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_SHORT_ID)}"
  UPSTREAM_SUBSCRIPTION_URL="${UPSTREAM_SUBSCRIPTION_URL:-$(load_kv_file_var "${UPSTREAM_ENV_FILE}" UPSTREAM_SUBSCRIPTION_URL)}"
}

_apply_upstream_defaults() {
  UPSTREAM_PORT="${UPSTREAM_PORT:-443}"
  UPSTREAM_FLOW="${UPSTREAM_FLOW:-xtls-rprx-vision}"
  UPSTREAM_FINGERPRINT="${UPSTREAM_FINGERPRINT:-chrome}"
  UPSTREAM_SERVER_NAME="${UPSTREAM_SERVER_NAME:-${UPSTREAM_ADDRESS:-}}"
}

# Full install / manual reconfigure. Explicit input given this run WINS and
# must succeed: a failed fetch/parse of explicitly-provided input is a hard
# error and does NOT silently fall back to a previously saved upstream. Only
# when no input is given this run do we reuse the saved upstream.env.
load_upstream_for_install() {
  UPSTREAM_CHANGED="false"

  if has_upstream_input; then
    if [ -n "${UPSTREAM_VLESS_URI:-}" ]; then
      if ! parse_upstream_vless_uri "${UPSTREAM_VLESS_URI}"; then
        print_missing_upstream_help
        exit 1
      fi
    elif [ -n "${UPSTREAM_SUBSCRIPTION_URL:-}" ] && \
         { [ -z "${UPSTREAM_ADDRESS:-}" ] || [ -z "${UPSTREAM_UUID:-}" ] || [ -z "${UPSTREAM_PUBLIC_KEY:-}" ]; }; then
      if ! refresh_upstream_from_subscription; then
        echo "Error: failed to fetch a valid upstream from ${UPSTREAM_SUBSCRIPTION_URL}." >&2
        echo "Explicit input was given this run, so the existing saved upstream is NOT reused." >&2
        print_missing_upstream_help
        exit 1
      fi
    fi
    # else: individual UPSTREAM_* fields were provided directly in the env.
  else
    _load_saved_upstream
  fi

  _apply_upstream_defaults
}

# Health check. Load the saved upstream, then best-effort refresh from the
# subscription if one is configured. A failed refresh keeps the existing saved
# upstream so a transient exit/network blip does not break a working relay.
load_upstream_for_healthcheck() {
  UPSTREAM_CHANGED="false"
  _load_saved_upstream

  if [ -n "${UPSTREAM_SUBSCRIPTION_URL:-}" ]; then
    if ! refresh_upstream_from_subscription; then
      echo "Warning: upstream subscription refresh failed; keeping the existing saved upstream."
    fi
  fi

  _apply_upstream_defaults
}

validate_upstream_config() {
  if [ -z "${UPSTREAM_ADDRESS:-}" ] || [ -z "${UPSTREAM_UUID:-}" ] || [ -z "${UPSTREAM_PUBLIC_KEY:-}" ]; then
    echo "Error: upstream exit parameters are incomplete." >&2
    echo "Provide UPSTREAM_VLESS_URI, UPSTREAM_SUBSCRIPTION_URL, or the individual" >&2
    echo "UPSTREAM_ADDRESS / UPSTREAM_UUID / UPSTREAM_PUBLIC_KEY (and SERVER_NAME / SHORT_ID)." >&2
    exit 1
  fi

  if ! printf '%s' "${UPSTREAM_ADDRESS}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: UPSTREAM_ADDRESS contains invalid characters: ${UPSTREAM_ADDRESS}" >&2
    exit 1
  fi
  validate_port_number UPSTREAM_PORT "${UPSTREAM_PORT}"

  if ! printf '%s' "${UPSTREAM_UUID}" | grep -Eq '^[0-9a-fA-F-]{36}$'; then
    echo "Error: UPSTREAM_UUID format is invalid: ${UPSTREAM_UUID}" >&2
    exit 1
  fi
  if ! printf '%s' "${UPSTREAM_PUBLIC_KEY}" | grep -Eq '^[A-Za-z0-9_-]{40,60}$'; then
    echo "Error: UPSTREAM_PUBLIC_KEY format is invalid or contains unsafe characters." >&2
    exit 1
  fi
  if ! printf '%s' "${UPSTREAM_SHORT_ID:-}" | grep -Eq '^[A-Fa-f0-9]{0,16}$'; then
    echo "Error: UPSTREAM_SHORT_ID must be hex and at most 16 characters, got: ${UPSTREAM_SHORT_ID:-}" >&2
    exit 1
  fi
  if ! printf '%s' "${UPSTREAM_SERVER_NAME}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: UPSTREAM_SERVER_NAME contains invalid characters: ${UPSTREAM_SERVER_NAME}" >&2
    exit 1
  fi
  if ! printf '%s' "${UPSTREAM_FLOW}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: UPSTREAM_FLOW contains invalid characters: ${UPSTREAM_FLOW}" >&2
    exit 1
  fi
  if ! printf '%s' "${UPSTREAM_FINGERPRINT}" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    echo "Error: UPSTREAM_FINGERPRINT contains invalid characters: ${UPSTREAM_FINGERPRINT}" >&2
    exit 1
  fi
}

save_upstream_env() {
  write_kv_env_file "${UPSTREAM_ENV_FILE}" \
    UPSTREAM_ADDRESS "${UPSTREAM_ADDRESS}" \
    UPSTREAM_PORT "${UPSTREAM_PORT}" \
    UPSTREAM_UUID "${UPSTREAM_UUID}" \
    UPSTREAM_FLOW "${UPSTREAM_FLOW}" \
    UPSTREAM_SERVER_NAME "${UPSTREAM_SERVER_NAME}" \
    UPSTREAM_FINGERPRINT "${UPSTREAM_FINGERPRINT}" \
    UPSTREAM_PUBLIC_KEY "${UPSTREAM_PUBLIC_KEY}" \
    UPSTREAM_SHORT_ID "${UPSTREAM_SHORT_ID:-}" \
    UPSTREAM_SUBSCRIPTION_URL "${UPSTREAM_SUBSCRIPTION_URL:-}"
}
