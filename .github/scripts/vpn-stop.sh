#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

DEFAULTS_FILE="${SCRIPT_DIR}/vpn-defaults.sh"

if [[ ! -f "${DEFAULTS_FILE}" ]]; then
    echo "VPN defaults file not found: ${DEFAULTS_FILE}" >&2
    exit 1
fi

# shellcheck source=vpn-defaults.sh
source "${DEFAULTS_FILE}"

log()
{
    printf '[vpn] %s\n' "$*"
}

log "Disconnecting L2TP connection: ${VPN_CONNECTION_NAME}"

if [[ -e /var/run/xl2tpd/l2tp-control ]]; then
    echo "d ${VPN_CONNECTION_NAME}" |
        sudo tee /var/run/xl2tpd/l2tp-control >/dev/null ||
        true
fi

for ((i = 0; i < VPN_DISCONNECT_TIMEOUT_SEC; i++)); do
    if ! ip link show "${VPN_PPP_INTERFACE}" >/dev/null 2>&1; then
        break
    fi

    sleep 1
done

if ip link show "${VPN_PPP_INTERFACE}" >/dev/null 2>&1; then
    echo \
        "PPP interface ${VPN_PPP_INTERFACE} still exists after ${VPN_DISCONNECT_TIMEOUT_SEC}s." \
        >&2
fi

log "Disconnecting IPsec connection: ${VPN_CONNECTION_NAME}"

sudo ipsec down "${VPN_CONNECTION_NAME}" >/dev/null 2>&1 ||
    true

log "VPN disconnected"
