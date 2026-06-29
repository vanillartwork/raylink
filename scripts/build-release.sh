#!/usr/bin/env bash
set -euo pipefail

# Build a versioned RayLink release tarball from src/.
#
# Output: dist/raylink-<version>.tar.gz
#
# The archive extracts to raylink-<version>/src/... so that install.sh can
# locate the src/ tree the same way it does for a GitHub branch tarball:
#   RAYLINK_TARBALL_URL=.../raylink-<version>.tar.gz \
#     curl -fsSL .../install.sh | sudo bash -s -- terminal

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"
DIST_DIR="${REPO_ROOT}/dist"

if [ ! -f "${SRC_DIR}/VERSION" ]; then
  echo "Error: ${SRC_DIR}/VERSION not found." >&2
  exit 1
fi

VERSION="$(tr -d ' \r\n\t' < "${SRC_DIR}/VERSION")"
STAGE_NAME="raylink-${VERSION}"
TARBALL="${DIST_DIR}/${STAGE_NAME}.tar.gz"

echo "Building RayLink ${VERSION}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

mkdir -p "${tmp_dir}/${STAGE_NAME}"
cp -a "${SRC_DIR}" "${tmp_dir}/${STAGE_NAME}/src"

mkdir -p "${DIST_DIR}"
tar -C "${tmp_dir}" -czf "${TARBALL}" "${STAGE_NAME}"

echo "Wrote ${TARBALL}"
echo "Contents:"
tar -tzf "${TARBALL}" | sed 's/^/  /'
