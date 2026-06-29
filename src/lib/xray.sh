#!/usr/bin/env bash
# Xray-core installation, service identity, systemd unit, and server config.

install_xray() {
  if [ -x "${XRAY_BIN}" ]; then
    "${XRAY_BIN}" version || true
    return 0
  fi

  echo "Installing Xray-core from GitHub latest release..."

  local arch xray_arch tmp_dir download_url found_bin prev_exit_trap_action
  local xray_repo xray_api_url xray_url_prefix xray_download_url api_url
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

  # Download configuration. XRAY_DOWNLOAD_URL is the main escape hatch: a direct
  # zip URL that skips the GitHub API entirely. XRAY_URL_PREFIX (falling back to
  # GITHUB_URL_PREFIX) proxies the API and asset URLs.
  xray_repo="${XRAY_REPO:-XTLS/Xray-core}"
  xray_api_url="${XRAY_API_URL:-https://api.github.com/repos/${xray_repo}/releases/latest}"
  xray_url_prefix="${XRAY_URL_PREFIX:-${GITHUB_URL_PREFIX:-}}"
  xray_download_url="${XRAY_DOWNLOAD_URL:-}"

  # Preserve any existing EXIT trap. Do not use eval on the full trap -p output.
  prev_exit_trap_action="$(trap -p EXIT | sed "s/^trap -- '//;s/' EXIT$//" || true)"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT
  cd "${tmp_dir}"

  if [ -n "${xray_download_url}" ]; then
    download_url="${xray_download_url}"
  else
    # Fetch release metadata to a file (easier to inspect than a shell variable
    # when GitHub returns an HTML error page or a rate-limit response).
    api_url="$(apply_url_prefix "${xray_url_prefix}" "${xray_api_url}")"
    if ! fetch_file "${api_url}" release.json; then
      echo "Failed to fetch Xray release metadata from: ${api_url}" >&2
      echo "GitHub may be slow, blocked, or rate-limiting. Retry with one of:" >&2
      echo "  XRAY_DOWNLOAD_URL=https://.../Xray-linux-${xray_arch}.zip   (skip the GitHub API)" >&2
      echo "  GITHUB_URL_PREFIX=https://your-proxy/                        (proxy GitHub)" >&2
      exit 1
    fi
    if command -v jq >/dev/null 2>&1; then
      download_url="$(jq -r ".assets[] | select(.name | test(\"Xray-linux-${xray_arch}\\\\.zip\")) | .browser_download_url" release.json | head -n 1)"
      [ "${download_url}" = "null" ] && download_url=""
    else
      download_url="$(grep -oE "https://[^\"]+Xray-linux-${xray_arch}\.zip" release.json | head -n 1)"
    fi

    if [ -z "${download_url}" ]; then
      echo "Failed to find an Xray download URL for linux-${xray_arch} in the release metadata." >&2
      echo "Set XRAY_DOWNLOAD_URL to a direct Xray-linux-${xray_arch}.zip URL to bypass the API." >&2
      exit 1
    fi
    download_url="$(apply_url_prefix "${xray_url_prefix}" "${download_url}")"
  fi

  if ! fetch_file "${download_url}" xray.zip; then
    echo "Failed to download Xray from: ${download_url}" >&2
    echo "Retry with XRAY_DOWNLOAD_URL=<direct zip url> or GITHUB_URL_PREFIX=<proxy prefix>." >&2
    exit 1
  fi

  # Integrity check: a proxy/error page saved as xray.zip would fail here.
  if ! unzip -t xray.zip >/dev/null 2>&1; then
    echo "Downloaded Xray archive failed its integrity check (corrupt, or not a zip): ${download_url}" >&2
    echo "This often means a proxy or error page was downloaded instead of the zip." >&2
    echo "Try a different XRAY_DOWNLOAD_URL or GITHUB_URL_PREFIX." >&2
    exit 1
  fi
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
    XRAY_SERVICE_DESC XRAY_SERVICE_USER XRAY_SERVICE_GROUP XRAY_CONFIG_DIR INSTALL_DIR XRAY_BIN XRAY_CONFIG \
    > "/etc/systemd/system/${XRAY_SERVICE}"
}

# Build the optional top-level "metrics" block (default off; localhost only).
# Sets METRICS_BLOCK to either "" or a JSON snippet ending in ",\n" so it can be
# spliced into the config just before "inbounds".
build_metrics_block() {
  METRICS_BLOCK=""
  if is_true "${ENABLE_XRAY_METRICS:-false}"; then
    printf -v METRICS_BLOCK '  "metrics": {\n    "tag": "metrics",\n    "listen": "%s"\n  },\n' \
      "${METRICS_LISTEN:-127.0.0.1:11111}"
  fi
}

write_xray_config() {
  mkdir -p "${XRAY_CONFIG_DIR}"

  TFO_JSON_VALUE="false"
  if is_true "${ENABLE_TFO}"; then
    TFO_JSON_VALUE="true"
  fi
  build_metrics_block

  render_template "${RAYLINK_TEMPLATES}/xray/server.json.tmpl" \
    METRICS_BLOCK LISTEN_ADDRESS PORT UUID FLOW TFO_JSON_VALUE REALITY_DEST REALITY_SERVER_NAME PRIVATE_KEY SHORT_ID \
    > "${XRAY_CONFIG}"

  chown root:"${XRAY_SERVICE_GROUP}" "${XRAY_CONFIG}" 2>/dev/null || true
  chmod 640 "${XRAY_CONFIG}"
}

# Relay config: VLESS Reality inbound (relay-facing client params) plus a
# VLESS Reality outbound to the upstream terminal, with routing that sends all
# inbound traffic to the upstream. Inbound params reuse the standard variable
# names (UUID, PRIVATE_KEY, ...); upstream params use UPSTREAM_* variables.
write_relay_xray_config() {
  mkdir -p "${XRAY_CONFIG_DIR}"

  TFO_JSON_VALUE="false"
  if is_true "${ENABLE_TFO}"; then
    TFO_JSON_VALUE="true"
  fi
  build_metrics_block

  render_template "${RAYLINK_TEMPLATES}/xray/relay-server.json.tmpl" \
    METRICS_BLOCK LISTEN_ADDRESS PORT UUID FLOW TFO_JSON_VALUE REALITY_DEST REALITY_SERVER_NAME PRIVATE_KEY SHORT_ID \
    UPSTREAM_ADDRESS UPSTREAM_PORT UPSTREAM_UUID UPSTREAM_FLOW UPSTREAM_SERVER_NAME \
    UPSTREAM_FINGERPRINT UPSTREAM_PUBLIC_KEY UPSTREAM_SHORT_ID \
    > "${XRAY_CONFIG}"

  chown root:"${XRAY_SERVICE_GROUP}" "${XRAY_CONFIG}" 2>/dev/null || true
  chmod 640 "${XRAY_CONFIG}"
}
