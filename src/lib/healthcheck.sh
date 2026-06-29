#!/usr/bin/env bash
# Periodic health check: ensure runtime is healthy and install the systemd timer.

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

  write_healthcheck_env_file

  # In the modular layout the health check runs the installed CLI directly;
  # there is no self-copy. The CLI lives on disk under RAYLINK_LIB_DIR and is
  # linked at RAYLINK_CLI.
  HEALTHCHECK_EXEC="${RAYLINK_CLI} terminal --health-check"

  render_template "${RAYLINK_TEMPLATES}/systemd/healthcheck.service.tmpl" \
    XRAY_SERVICE HEALTHCHECK_ENV_FILE HEALTHCHECK_EXEC \
    > "/etc/systemd/system/${HEALTHCHECK_SERVICE_NAME}"

  render_template "${RAYLINK_TEMPLATES}/systemd/healthcheck.timer.tmpl" \
    HEALTHCHECK_ON_BOOT_SEC HEALTHCHECK_ON_UNIT_ACTIVE_SEC HEALTHCHECK_SERVICE_NAME \
    > "/etc/systemd/system/${HEALTHCHECK_TIMER_NAME}"

  systemctl daemon-reload
  systemctl enable --now "${HEALTHCHECK_TIMER_NAME}" >/dev/null 2>&1 || true
  echo "Health check timer enabled: ${HEALTHCHECK_TIMER_NAME} (boot delay ${HEALTHCHECK_ON_BOOT_SEC}, interval ${HEALTHCHECK_ON_UNIT_ACTIVE_SEC})"
}
