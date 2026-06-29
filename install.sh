#!/usr/bin/env bash
set -euo pipefail

# RayLink bootstrap installer.
#
# One-line usage:
#   curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash
#
# Install and immediately run a command (anything after `--` is passed to raylink):
#   curl -fsSL .../install.sh | sudo bash -s -- terminal
#   curl -fsSL .../install.sh | sudo env PORT=8443 bash -s -- terminal
#
# This script downloads the RayLink source tree, installs it under
# RAYLINK_LIB_DIR, links the `raylink` CLI into PATH, and optionally runs a
# command (defaults to no command when invoked directly, or `terminal` when
# invoked through the backward-compatible terminal.sh entrypoint).

RAYLINK_REPO="${RAYLINK_REPO:-vanillartwork/raylink}"
RAYLINK_REF="${RAYLINK_REF:-main}"
RAYLINK_LIB_DIR="${RAYLINK_LIB_DIR:-/usr/local/lib/raylink}"
RAYLINK_BIN_LINK="${RAYLINK_BIN_LINK:-/usr/local/bin/raylink}"
# Optional explicit tarball URL (e.g. a tagged release asset). When empty the
# GitHub branch tarball for RAYLINK_REF is used.
RAYLINK_TARBALL_URL="${RAYLINK_TARBALL_URL:-}"

log() { printf '%s\n' "$*"; }
err() { printf 'Error: %s\n' "$*" >&2; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Please run the installer as root, for example: curl -fsSL .../install.sh | sudo bash"
    exit 1
  fi
}

ensure_tools() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v tar  >/dev/null 2>&1 || missing+=(tar)
  if [ "${#missing[@]}" -gt 0 ]; then
    if command -v apt >/dev/null 2>&1; then
      apt update
      apt install -y "${missing[@]}"
    else
      err "Missing required tools: ${missing[*]}. Install them and rerun."
      exit 1
    fi
  fi
}

download_and_stage() {
  local tmp_dir tarball url extracted
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN

  if [ -n "${RAYLINK_TARBALL_URL}" ]; then
    url="${RAYLINK_TARBALL_URL}"
  else
    url="https://github.com/${RAYLINK_REPO}/archive/refs/heads/${RAYLINK_REF}.tar.gz"
  fi

  log "Downloading RayLink source: ${url}"
  tarball="${tmp_dir}/raylink.tar.gz"
  if ! curl -fsSL "${url}" -o "${tarball}"; then
    err "Failed to download RayLink source from ${url}"
    exit 1
  fi

  tar -xzf "${tarball}" -C "${tmp_dir}"

  # The branch tarball extracts to <repo>-<ref>/; locate the src directory.
  extracted="$(find "${tmp_dir}" -maxdepth 2 -type d -name src | head -n 1)"
  if [ -z "${extracted}" ] || [ ! -f "${extracted}/raylink" ]; then
    err "Downloaded archive does not contain a valid src/ tree."
    exit 1
  fi

  log "Installing RayLink into ${RAYLINK_LIB_DIR}"
  rm -rf "${RAYLINK_LIB_DIR}"
  mkdir -p "$(dirname "${RAYLINK_LIB_DIR}")"
  cp -a "${extracted}" "${RAYLINK_LIB_DIR}"

  chmod 755 "${RAYLINK_LIB_DIR}/raylink"
  find "${RAYLINK_LIB_DIR}/lib" "${RAYLINK_LIB_DIR}/commands" -type f -name '*.sh' -exec chmod 644 {} + 2>/dev/null || true

  mkdir -p "$(dirname "${RAYLINK_BIN_LINK}")"
  ln -sf "${RAYLINK_LIB_DIR}/raylink" "${RAYLINK_BIN_LINK}"
  log "Linked CLI: ${RAYLINK_BIN_LINK} -> ${RAYLINK_LIB_DIR}/raylink"
}

main() {
  require_root
  ensure_tools
  download_and_stage

  if [ "$#" -gt 0 ]; then
    log "Running: raylink $*"
    exec "${RAYLINK_BIN_LINK}" "$@"
  fi

  log ""
  log "RayLink installed. Run a command, for example:"
  log "  sudo raylink terminal"
  log "  sudo raylink terminal --health-check"
}

main "$@"
