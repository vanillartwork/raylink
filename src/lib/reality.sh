#!/usr/bin/env bash
# VLESS Reality credentials, target validation, self-test, and fallback.

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

warn_if_unexpected_x25519_key() {
  local label="$1"
  local value="$2"
  if ! printf '%s' "${value}" | grep -Eq '^[A-Za-z0-9_-]{40,50}$'; then
    echo "Warning: ${label} format looks unexpected: ${value:0:10}..."
  fi
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

  save_reality_env
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

run_reality_self_test_once() {
  if ! is_true "${REALITY_SELF_TEST}"; then
    echo "Skip Reality self-test because REALITY_SELF_TEST=false"
    return 0
  fi

  local tmp_cfg tmp_log pid curl_rc
  TEST_PORT="$(select_free_local_port "${REALITY_SELF_TEST_SOCKS_PORT}")"
  tmp_cfg="$(mktemp /tmp/raylink-reality-self-test.XXXXXX.json)"
  tmp_log="$(mktemp /tmp/raylink-reality-self-test.XXXXXX.log)"

  render_template "${RAYLINK_TEMPLATES}/xray/selftest-client.json.tmpl" \
    TEST_PORT PORT UUID FLOW REALITY_SERVER_NAME CLIENT_FINGERPRINT PUBLIC_KEY SHORT_ID \
    > "${tmp_cfg}"

  "${XRAY_BIN}" run -config "${tmp_cfg}" >"${tmp_log}" 2>&1 &
  pid="$!"
  sleep 1

  curl_rc=1
  if kill -0 "${pid}" >/dev/null 2>&1; then
    if timeout "$((REALITY_SELF_TEST_TIMEOUT + 5))" \
      curl -fsS -x "socks5h://127.0.0.1:${TEST_PORT}" \
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
