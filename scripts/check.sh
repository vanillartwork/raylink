#!/usr/bin/env bash
set -euo pipefail

# Lint and sanity-check the RayLink sources.
#   - bash -n syntax check on every shell script
#   - shellcheck (if installed)
#   - a template render dry-run using sample values

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"

rc=0

echo "== bash -n syntax check =="
mapfile -t scripts < <(
  {
    printf '%s\n' "${REPO_ROOT}/install.sh"
    printf '%s\n' "${SRC_DIR}/raylink"
    find "${SRC_DIR}/lib" "${SRC_DIR}/commands" -type f -name '*.sh'
    find "${REPO_ROOT}/scripts" -type f -name '*.sh'
  } 2>/dev/null
)
for s in "${scripts[@]}"; do
  [ -f "${s}" ] || continue
  if bash -n "${s}"; then
    echo "  ok: ${s#"${REPO_ROOT}"/}"
  else
    echo "  FAIL: ${s#"${REPO_ROOT}"/}"
    rc=1
  fi
done

echo ""
echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  # lib/commands files are sourced, so external/unassigned vars are expected.
  shellcheck -S warning -e SC1090,SC1091,SC2034,SC2154 "${scripts[@]}" || rc=1
else
  echo "  shellcheck not installed; skipping."
fi

echo ""
echo "== template render dry-run =="
if command -v envsubst >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  RAYLINK_TEMPLATES="${SRC_DIR}/templates"
  . "${SRC_DIR}/lib/common.sh"

  PORT=443 SUB_PORT=8080 SUB_ROOT=/opt/x/public SUB_RATE_LIMIT=30r/m SUB_RATE_BURST=10 \
  SUB_LIMIT_ZONE=cloud_xray_sub_limit \
  UUID=11111111-1111-1111-1111-111111111111 FLOW=xtls-rprx-vision TFO_JSON_VALUE=false \
  LISTEN_ADDRESS=0.0.0.0 REALITY_DEST=www.cloudflare.com:443 REALITY_SERVER_NAME=www.cloudflare.com \
  PRIVATE_KEY=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa SHORT_ID=0123456789abcdef \
  UPSTREAM_ADDRESS=203.0.113.10 UPSTREAM_PORT=443 UPSTREAM_UUID=22222222-2222-2222-2222-222222222222 \
  UPSTREAM_FLOW=xtls-rprx-vision UPSTREAM_SERVER_NAME=www.apple.com UPSTREAM_FINGERPRINT=safari \
  UPSTREAM_PUBLIC_KEY=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb UPSTREAM_SHORT_ID=abcdef0123456789 \
  bash -c '
    set -e
    RAYLINK_TEMPLATES="'"${RAYLINK_TEMPLATES}"'"
    . "'"${SRC_DIR}"'/lib/common.sh"
    render_template "${RAYLINK_TEMPLATES}/xray/server.json.tmpl" \
      LISTEN_ADDRESS PORT UUID FLOW TFO_JSON_VALUE REALITY_DEST REALITY_SERVER_NAME PRIVATE_KEY SHORT_ID \
      | python3 -m json.tool >/dev/null && echo "  ok: xray/server.json.tmpl renders valid JSON"
    render_template "${RAYLINK_TEMPLATES}/xray/relay-server.json.tmpl" \
      LISTEN_ADDRESS PORT UUID FLOW TFO_JSON_VALUE REALITY_DEST REALITY_SERVER_NAME PRIVATE_KEY SHORT_ID \
      UPSTREAM_ADDRESS UPSTREAM_PORT UPSTREAM_UUID UPSTREAM_FLOW UPSTREAM_SERVER_NAME \
      UPSTREAM_FINGERPRINT UPSTREAM_PUBLIC_KEY UPSTREAM_SHORT_ID \
      | python3 -m json.tool >/dev/null && echo "  ok: xray/relay-server.json.tmpl renders valid JSON"
    render_template "${RAYLINK_TEMPLATES}/nginx/subscription.conf.tmpl" \
      SUB_LIMIT_ZONE SUB_RATE_LIMIT SUB_PORT SUB_ROOT SUB_RATE_BURST \
      | grep -q "binary_remote_addr" && echo "  ok: nginx template preserves nginx \$variables"
  ' || rc=1
else
  echo "  envsubst not installed; skipping."
fi

echo ""
if [ "${rc}" -eq 0 ]; then
  echo "All checks passed."
else
  echo "Some checks failed."
fi
exit "${rc}"
