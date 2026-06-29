#!/usr/bin/env bash
# RayLink relay command: full install and lightweight health check.
#
# A relay exposes a VLESS Reality inbound to clients and forwards ALL of that
# traffic to an upstream terminal node (Client -> Relay -> Terminal -> Internet).
# Orchestration only; reusable logic lives in lib/*.sh. The relay reuses the
# standard inbound variables (UUID, PRIVATE_KEY, ...) for its client-facing
# Reality endpoint, and UPSTREAM_* variables for the link to the terminal.

# Persist the relay runtime environment for timer-invoked health checks.
write_relay_healthcheck_env_file() {
  write_kv_env_file "${HEALTHCHECK_ENV_FILE}" \
    PORT "${PORT}" \
    NODE_NAME "${NODE_NAME}" \
    NODE_ROLE "${NODE_ROLE}" \
    INSTALL_DIR "${INSTALL_DIR}" \
    XRAY_BIN "${XRAY_BIN}" \
    XRAY_CONFIG_DIR "${XRAY_CONFIG_DIR}" \
    XRAY_CONFIG "${XRAY_CONFIG}" \
    XRAY_SHARE_DIR "${XRAY_SHARE_DIR}" \
    XRAY_SERVICE "${XRAY_SERVICE}" \
    XRAY_SERVICE_DESC "${XRAY_SERVICE_DESC}" \
    XRAY_SERVICE_USER "${XRAY_SERVICE_USER}" \
    XRAY_SERVICE_GROUP "${XRAY_SERVICE_GROUP}" \
    REALITY_ENV_FILE "${REALITY_ENV_FILE}" \
    CLASH_FILE "${CLASH_FILE}" \
    INFO_FILE "${INFO_FILE}" \
    VLESS_FILE "${VLESS_FILE}" \
    VLESS_URI_LIST_FILE "${VLESS_URI_LIST_FILE}" \
    UPSTREAM_ENV_FILE "${UPSTREAM_ENV_FILE}" \
    UPSTREAM_SUBSCRIPTION_URL "${UPSTREAM_SUBSCRIPTION_URL:-}" \
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
    SUB_LIMIT_ZONE "${SUB_LIMIT_ZONE}" \
    NGINX_SITE "${NGINX_SITE}" \
    NGINX_SITE_LINK "${NGINX_SITE_LINK}" \
    SUB_RATE_LIMIT "${SUB_RATE_LIMIT}" \
    SUB_RATE_BURST "${SUB_RATE_BURST}"
}

append_upstream_info() {
  cat >> "${INFO_FILE}" <<UPSTREAM_INFO_EOF

Upstream terminal (relay -> terminal, kept on this server only):
  Address:        ${UPSTREAM_ADDRESS}
  Port:           ${UPSTREAM_PORT}
  Flow:           ${UPSTREAM_FLOW}
  SNI:            ${UPSTREAM_SERVER_NAME}
  Fingerprint:    ${UPSTREAM_FINGERPRINT}
  Short ID:       ${UPSTREAM_SHORT_ID:-}
  Subscription:   ${UPSTREAM_SUBSCRIPTION_URL:-(none)}

Note: the client subscription above exposes ONLY the relay. Upstream terminal
parameters are never published to clients.
UPSTREAM_INFO_EOF
  chmod 600 "${INFO_FILE}"
}

run_relay_healthcheck_mode() {
  require_root

  if [ -z "${ENABLE_SUBSCRIPTION_WAS_SET}" ] && [ ! -f "${SUB_ENV_FILE}" ]; then
    ENABLE_SUBSCRIPTION="false"
  fi

  validate_common_ports

  echo "=========================================="
  echo " RayLink relay health check"
  echo "=========================================="

  if [ ! -x "${XRAY_BIN}" ]; then
    echo "Error: Xray binary not found at ${XRAY_BIN}. Run the full installer first."
    exit 1
  fi

  mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"
  detect_public_ip_and_resolve_dns
  load_existing_reality_credentials_for_healthcheck

  # Refresh upstream from the terminal subscription if one is configured.
  load_upstream_config
  if [ -n "${UPSTREAM_SUBSCRIPTION_URL:-}" ]; then
    refresh_upstream_from_subscription || true
  fi
  validate_upstream_config
  save_upstream_env

  validate_reality_inputs
  ensure_xray_running_for_healthcheck

  # Apply upstream changes immediately by rewriting the relay config.
  if is_true "${UPSTREAM_CHANGED}"; then
    echo "Upstream changed; rewriting relay config and restarting service."
    restart_xray_with_current_reality_target
  fi

  perform_reality_self_test_with_fallbacks
  sync_client_outputs

  echo "Relay health check complete. Client files and subscription data are up to date."
  echo "Current public IPv4: ${PUBLIC_IP}"
  echo "Upstream terminal: ${UPSTREAM_ADDRESS}:${UPSTREAM_PORT}"
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Subscription URL: ${SUBSCRIPTION_URL_CLASH}"
  fi
}

run_relay_full_install() {
  require_root
  validate_common_ports

  # Fail fast before installing anything if no upstream source was provided
  # and none was previously saved.
  if [ -z "${UPSTREAM_SUBSCRIPTION_URL:-}" ] && [ -z "${UPSTREAM_VLESS_URI:-}" ] \
     && [ -z "${UPSTREAM_ADDRESS:-}" ] && [ ! -f "${UPSTREAM_ENV_FILE}" ]; then
    echo "Error: a relay requires an upstream terminal node. Provide one of:"
    echo "  UPSTREAM_SUBSCRIPTION_URL=http://TERMINAL_IP:8080/sub/TOKEN   (recommended)"
    echo "  UPSTREAM_VLESS_URI='vless://...'                              (terminal link)"
    echo "  UPSTREAM_ADDRESS=.. UPSTREAM_UUID=.. UPSTREAM_PUBLIC_KEY=..   (individual fields)"
    echo "Nothing was installed. See docs/relay.md."
    exit 1
  fi

  echo "=========================================="
  echo " Xray VLESS Reality Relay Setup"
  echo "=========================================="

  echo "[1/13] Installing required packages..."
  install_required_packages

  echo "[2/13] Applying TCP tuning..."
  apply_tcp_tuning

  echo "[3/13] Preparing directories..."
  mkdir -p "${INSTALL_DIR}" "${XRAY_CONFIG_DIR}" "${XRAY_SHARE_DIR}"

  echo "[4/13] Detecting public IPv4 and selecting DNS profile..."
  detect_public_ip_and_resolve_dns

  echo "[5/13] Stopping any existing relay service on this port..."
  systemctl stop "${XRAY_SERVICE}" >/dev/null 2>&1 || true

  echo "[6/13] Installing Xray-core..."
  install_xray

  echo "[7/13] Loading or generating relay inbound VLESS/Reality credentials..."
  load_or_generate_reality_credentials

  echo "[8/13] Loading upstream terminal parameters..."
  load_upstream_config
  validate_upstream_config
  save_upstream_env
  echo "Upstream terminal: ${UPSTREAM_ADDRESS}:${UPSTREAM_PORT} (SNI ${UPSTREAM_SERVER_NAME})"

  echo "[9/13] Checking relay inbound Reality target..."
  check_reality_target

  echo "[10/13] Writing relay Xray config and systemd service..."
  ensure_xray_service_identity
  validate_reality_inputs
  write_relay_xray_config
  write_xray_service

  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG}"

  systemctl daemon-reload
  systemctl enable "${XRAY_SERVICE}" >/dev/null 2>&1
  systemctl restart "${XRAY_SERVICE}"

  sleep 1

  if ! systemctl is-active --quiet "${XRAY_SERVICE}"; then
    echo "Relay Xray failed to start."
    systemctl status "${XRAY_SERVICE}" --no-pager || true
    journalctl -u "${XRAY_SERVICE}" -n 80 --no-pager || true
    exit 1
  fi

  echo "[11/13] Running end-to-end relay self-test (Client -> Relay -> Terminal -> Internet)..."
  perform_reality_self_test_with_fallbacks

  echo "[12/13] Generating relay client config and subscription..."
  sync_client_outputs
  append_upstream_info

  echo "[13/13] Configuring periodic relay health check..."
  install_healthcheck_timer

  echo ""
  echo "=========================================="
  echo "Relay setup complete"
  echo "=========================================="
  echo "Full server information saved to: ${INFO_FILE}"
  echo "VLESS direct import link saved to: ${VLESS_FILE}"
  echo "Upstream terminal: ${UPSTREAM_ADDRESS}:${UPSTREAM_PORT}"

  echo ""
  echo "Relay Xray status:"
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
  echo "Important: allow TCP ${PORT} in the relay firewall/security group for clients."
  echo "On the TERMINAL server, allow TCP ${UPSTREAM_PORT} from this relay's IP (${PUBLIC_IP})."
  echo "Clients connect only to the relay; the terminal can be restricted to the relay IP."
  if is_true "${ENABLE_SUBSCRIPTION}"; then
    echo "Important: allow TCP ${SUB_PORT} if you want to access the relay subscription URLs."
    echo "Plain HTTP subscription warning: use only on trusted networks, or restrict ${SUB_PORT} by firewall/source IP."
  fi
  if is_true "${ENABLE_HEALTHCHECK_TIMER}"; then
    echo "Health check timer: ${HEALTHCHECK_TIMER_NAME}"
  fi
}

# Map RELAY_* aliases onto the standard inbound variable names so the shared
# reality/xray/client-output logic can be reused unchanged.
relay_map_inbound_aliases() {
  [ -n "${RELAY_PORT:-}" ]                && PORT="${RELAY_PORT}"
  [ -n "${RELAY_NODE_NAME:-}" ]           && NODE_NAME="${RELAY_NODE_NAME}"
  [ -n "${RELAY_UUID:-}" ]                && UUID="${RELAY_UUID}"
  [ -n "${RELAY_PRIVATE_KEY:-}" ]         && PRIVATE_KEY="${RELAY_PRIVATE_KEY}"
  [ -n "${RELAY_PUBLIC_KEY:-}" ]          && PUBLIC_KEY="${RELAY_PUBLIC_KEY}"
  [ -n "${RELAY_SHORT_ID:-}" ]            && SHORT_ID="${RELAY_SHORT_ID}"
  [ -n "${RELAY_REALITY_DEST:-}" ]        && REALITY_DEST="${RELAY_REALITY_DEST}"
  [ -n "${RELAY_REALITY_SERVER_NAME:-}" ] && REALITY_SERVER_NAME="${RELAY_REALITY_SERVER_NAME}"
  [ -n "${RELAY_CLIENT_FINGERPRINT:-}" ]  && CLIENT_FINGERPRINT="${RELAY_CLIENT_FINGERPRINT}"
  [ -n "${RELAY_FLOW:-}" ]                && FLOW="${RELAY_FLOW}"
  return 0
}

relay_main() {
  # Capture before defaults assign ENABLE_SUBSCRIPTION via :=.
  ENABLE_SUBSCRIPTION_WAS_SET="${ENABLE_SUBSCRIPTION+x}"

  relay_map_inbound_aliases

  local healthcheck_only="false"
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --health-check|--healthcheck|healthcheck)
        healthcheck_only="true"
        ;;
      *)
        echo "Unknown argument: ${arg}"
        exit 1
        ;;
    esac
  done

  # shellcheck source=/dev/null
  . "${RAYLINK_DEFAULTS}/relay.env"
  # shellcheck source=/dev/null
  . "${RAYLINK_DEFAULTS}/legacy.env"

  # Dependency-injection hooks consumed by the shared libs.
  XRAY_CONFIG_WRITER="write_relay_xray_config"
  HEALTHCHECK_ENV_WRITER="write_relay_healthcheck_env_file"

  if is_true "${healthcheck_only}"; then
    run_relay_healthcheck_mode
  else
    run_relay_full_install
  fi
}
