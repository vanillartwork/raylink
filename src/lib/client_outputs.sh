#!/usr/bin/env bash
# Generate client-facing outputs: Clash/Mihomo YAML, VLESS URI, info file.

write_clash_config() {
  TFO_YAML_VALUE="false"
  if is_true "${ENABLE_TFO}"; then
    TFO_YAML_VALUE="true"
  fi

  # Static header, then the selected DNS profile, then the rendered proxies.
  cat "${RAYLINK_TEMPLATES}/clash/base.yaml.tmpl" > "${CLASH_FILE}"
  write_dns_config >> "${CLASH_FILE}"
  render_template "${RAYLINK_TEMPLATES}/clash/proxies.yaml.tmpl" \
    NODE_NAME PUBLIC_IP PORT UUID TFO_YAML_VALUE REALITY_SERVER_NAME FLOW CLIENT_FINGERPRINT PUBLIC_KEY SHORT_ID \
    >> "${CLASH_FILE}"

  chmod 644 "${CLASH_FILE}"
}

assemble_vless_uri() {
  URLENCODED_NODE_NAME="$(urlencode "${NODE_NAME}")"
  # PUBLIC_URI_HOST brackets IPv6 literals; equals PUBLIC_IP for IPv4/hostnames.
  VLESS_URI="vless://${UUID}@${PUBLIC_URI_HOST:-${PUBLIC_IP}}:${PORT}?encryption=none&security=reality&sni=${REALITY_SERVER_NAME}&fp=${CLIENT_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=${FLOW}#${URLENCODED_NODE_NAME}"
  printf '%s\n' "${VLESS_URI}" > "${VLESS_FILE}"
  chmod 644 "${VLESS_FILE}"
}

write_uri_list_sub() {
  # Trailing newline required by some subscription clients.
  printf '%s\n' "${VLESS_URI}" | base64_one_line > "${VLESS_URI_LIST_FILE}"
  printf '\n' >> "${VLESS_URI_LIST_FILE}"
  chmod 644 "${VLESS_URI_LIST_FILE}"
}

write_info_file() {
  cat > "${INFO_FILE}" <<INFO_EOF
Server information:
Node role: ${NODE_ROLE:-Exit}
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
  Universal Subscription URL:
    ${SUBSCRIPTION_URL_UNIVERSAL}
  Clash Subscription URL:
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
  To re-enable: sudo raylink ${RAYLINK_COMMAND:-exit} (with ENABLE_SUBSCRIPTION=true)
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
