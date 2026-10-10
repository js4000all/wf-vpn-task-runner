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

#
# Export context that is only available after the VPN connection
# has actually been established.
#
DEFAULTS_FILE="${SCRIPT_DIR}/vpn-defaults.sh"
source "${DEFAULTS_FILE}"

export VPN_CONTEXT_ACTIVE=true
export VPN_CONTEXT_INTERFACE="${VPN_PPP_INTERFACE}"

VPN_CONTEXT_LOCAL_IP="$(
    ip -4 -o addr show dev "${VPN_PPP_INTERFACE}" |
        awk '{split($4, a, "/"); print a[1]; exit}'
)"
export VPN_CONTEXT_LOCAL_IP

VPN_CONTEXT_PEER_IP="$(
    ip -4 -o addr show dev "${VPN_PPP_INTERFACE}" |
        awk '{
            for (i = 1; i <= NF; i++) {
                if ($i == "peer") {
                    split($(i + 1), a, "/")
                    print a[1]
                    exit
                }
            }
        }'
)"
export VPN_CONTEXT_PEER_IP

export VPN_CONTEXT_CHECK_HOST_IP="${VPN_CHECK_HOST_IP}"
export VPN_CONTEXT_SERVER_IP="${VPN_SERVER_IP}"

echo "Running command in VPN context..."

"$@"
