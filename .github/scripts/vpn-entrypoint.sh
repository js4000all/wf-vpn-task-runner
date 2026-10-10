#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="${GITHUB_WORKSPACE:-$PWD}"
: "${VPN_ENTRYPOINT_SCRIPT:?VPN_ENTRYPOINT_SCRIPT is required}"

if [[ "${VPN_ENTRYPOINT_SCRIPT}" = /* ]]; then
    ENTRYPOINT_PATH="${VPN_ENTRYPOINT_SCRIPT}"
else
    ENTRYPOINT_PATH="${REPOSITORY_ROOT}/${VPN_ENTRYPOINT_SCRIPT}"
fi

if [[ ! -f "${ENTRYPOINT_PATH}" ]]; then
    echo "VPN entrypoint script not found: ${VPN_ENTRYPOINT_SCRIPT}" >&2
    exit 1
fi

echo "[vpn] Running entrypoint: ${VPN_ENTRYPOINT_SCRIPT}"

exec bash "${ENTRYPOINT_PATH}"
