#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="${GITHUB_WORKSPACE:-$PWD}"
DEFAULT_ENTRYPOINT=".github/vpn/example.sh"

ENTRYPOINT="${VPN_ENTRYPOINT_SCRIPT:-${DEFAULT_ENTRYPOINT}}"

if [[ "${ENTRYPOINT}" = /* ]]; then
    ENTRYPOINT_PATH="${ENTRYPOINT}"
else
    ENTRYPOINT_PATH="${REPOSITORY_ROOT}/${ENTRYPOINT}"
fi

if [[ ! -f "${ENTRYPOINT_PATH}" ]]; then
    echo "VPN entrypoint script not found: ${ENTRYPOINT}" >&2
    exit 1
fi

echo "[vpn] Running entrypoint: ${ENTRYPOINT}"

exec bash "${ENTRYPOINT_PATH}"
