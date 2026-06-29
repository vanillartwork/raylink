#!/usr/bin/env bash
# Xray-core installation, service identity, systemd unit, and server config.

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

write_xray_service() {
  render_template "${RAYLINK_TEMPLATES}/systemd/xray.service.tmpl" \
    XRAY_SERVICE_USER XRAY_SERVICE_GROUP XRAY_CONFIG_DIR INSTALL_DIR XRAY_BIN XRAY_CONFIG \
    > "/etc/systemd/system/${XRAY_SERVICE}"
}

write_xray_config() {
  mkdir -p "${XRAY_CONFIG_DIR}"

  TFO_JSON_VALUE="false"
  if is_true "${ENABLE_TFO}"; then
    TFO_JSON_VALUE="true"
  fi

  render_template "${RAYLINK_TEMPLATES}/xray/server.json.tmpl" \
    LISTEN_ADDRESS PORT UUID FLOW TFO_JSON_VALUE REALITY_DEST REALITY_SERVER_NAME PRIVATE_KEY SHORT_ID \
    > "${XRAY_CONFIG}"

  chown root:"${XRAY_SERVICE_GROUP}" "${XRAY_CONFIG}" 2>/dev/null || true
  chmod 640 "${XRAY_CONFIG}"
}
