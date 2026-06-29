#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible RayLink terminal entrypoint.
#
# Preserves the original one-line install command:
#   curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/terminal.sh | sudo bash
#   curl -fsSL .../terminal.sh | sudo env PORT=8443 bash
#
# It bootstraps the modular installer and then runs `raylink terminal`.
# Environment variables (PORT, ENABLE_SUBSCRIPTION, etc.) are inherited as-is.

RAYLINK_REPO="${RAYLINK_REPO:-vanillartwork/raylink}"
RAYLINK_REF="${RAYLINK_REF:-main}"

installer="$(curl -fsSL "https://raw.githubusercontent.com/${RAYLINK_REPO}/${RAYLINK_REF}/install.sh")"
if [ -z "${installer}" ]; then
  echo "Error: failed to download the RayLink installer." >&2
  exit 1
fi

# Run the installer, passing the terminal command (plus any extra args).
exec bash -c "${installer}" raylink-install terminal "$@"
