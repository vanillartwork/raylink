#!/usr/bin/env bash
# HTTP subscription hosting through nginx.

validate_subscription_token() {
  local token="${1:-}"
  printf '%s' "${token}" | grep -Eq '^[A-Za-z0-9_-]{24,128}$'
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

  # PUBLIC_URL_HOST brackets IPv6 literals; equals PUBLIC_IP for IPv4/hostnames.
  local url_host="${PUBLIC_URL_HOST:-${PUBLIC_IP}}"
  SUB_DIR="${SUB_ROOT}/sub/${SUB_TOKEN}"
  SUBSCRIPTION_URL_UNIVERSAL="http://${url_host}:${SUB_PORT}/sub/${SUB_TOKEN}"
  SUBSCRIPTION_URL_CLASH="http://${url_host}:${SUB_PORT}/sub/${SUB_TOKEN}/clash.yaml"
  # Legacy alias kept in subscription.env.
  SUBSCRIPTION_URL_VLESS="http://${url_host}:${SUB_PORT}/sub/${SUB_TOKEN}/vless"

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

  # Family-aware listen directive: IPv4 keeps "listen PORT;"; IPv6 uses [::].
  if [ "${PUBLIC_IP_FAMILY:-4}" = 6 ]; then
    NGINX_LISTEN_DIRECTIVE="listen [::]:${SUB_PORT};"
  else
    NGINX_LISTEN_DIRECTIVE="listen ${SUB_PORT};"
  fi

  render_template "${RAYLINK_TEMPLATES}/nginx/subscription.conf.tmpl" \
    SUB_LIMIT_ZONE SUB_RATE_LIMIT NGINX_LISTEN_DIRECTIVE SUB_ROOT SUB_RATE_BURST \
    > "${tmp_nginx_site}"

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
