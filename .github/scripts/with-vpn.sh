#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

VPN_START="${SCRIPT_DIR}/vpn-start.sh"
VPN_STOP="${SCRIPT_DIR}/vpn-stop.sh"

if [[ "${1:-}" == "--" ]]; then
    shift
fi

if (( $# == 0 )); then
    echo "Usage: $0 -- command [args...]" >&2
    exit 2
fi

cleanup()
{
    local exit_code=$?

    trap - EXIT

    echo "Cleaning up VPN connection..."

    "${VPN_STOP}" || true

    exit "${exit_code}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"${VPN_START}"

echo "Running command in VPN context..."

"$@"
