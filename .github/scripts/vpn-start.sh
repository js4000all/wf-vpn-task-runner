#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &&
    pwd
)"

DEFAULTS_FILE="${SCRIPT_DIR}/vpn-defaults.sh"

if [[ ! -f "${DEFAULTS_FILE}" ]]; then
    echo "VPN defaults file not found: ${DEFAULTS_FILE}" >&2
    exit 1
fi

# Defaults are defined as:
#   VAR="${VAR:-default}"
# so values already supplied via environment variables are preserved.
# shellcheck source=vpn-defaults.sh
source "${DEFAULTS_FILE}"

# Required per environment / user.
: "${VPN_SERVER_IP:?VPN_SERVER_IP is required}"
: "${VPN_USERNAME:?VPN_USERNAME is required}"
: "${VPN_CHECK_HOST_IP:?VPN_CHECK_HOST_IP is required}"

# Required secrets.
: "${VPN_PSK:?VPN_PSK is required}"
: "${VPN_PASSWORD:?VPN_PASSWORD is required}"

PPP_OPTIONS_FILE="/etc/ppp/options.${VPN_CONNECTION_NAME}"

umask 077

log()
{
    printf '[vpn] %s\n' "$*"
}

dump_diagnostics()
{
    echo "--- IPsec status ---" >&2
    sudo ipsec statusall >&2 || true

    echo "--- XFRM state ---" >&2
    sudo ip xfrm state >&2 || true

    echo "--- XFRM policy ---" >&2
    sudo ip xfrm policy >&2 || true

    echo "--- PPP interface ---" >&2
    ip -4 addr show dev "${VPN_PPP_INTERFACE}" >&2 || true

    echo "--- routes ---" >&2
    ip route >&2 || true

    echo "--- xl2tpd status ---" >&2
    sudo systemctl status xl2tpd --no-pager >&2 || true

    echo "--- recent VPN logs ---" >&2
    sudo journalctl \
        --no-pager \
        --since '2 minutes ago' |
        grep -Ei 'xl2tpd|pppd|l2tp|ppp|charon|ipsec' |
        tail -300 >&2 ||
        true
}

log "Configuring IPsec connection: ${VPN_CONNECTION_NAME}"

sudo tee /etc/ipsec.conf >/dev/null <<EOF
config setup
    uniqueids=no

conn ${VPN_CONNECTION_NAME}
    keyexchange=${VPN_IKE_VERSION}
    type=transport
    authby=psk

    left=%defaultroute
    leftprotoport=17/${VPN_L2TP_PORT}

    right=${VPN_SERVER_IP}
    rightid=${VPN_SERVER_IP}
    rightprotoport=17/${VPN_L2TP_PORT}

    ike=${VPN_IKE_PROPOSAL}
    esp=${VPN_ESP_PROPOSAL}

    ikelifetime=${VPN_IKE_LIFETIME}

    auto=add
EOF

printf ': PSK "%s"\n' "${VPN_PSK}" |
    sudo tee /etc/ipsec.secrets >/dev/null

sudo chmod 600 /etc/ipsec.secrets

log "Configuring xl2tpd"

sudo tee /etc/xl2tpd/xl2tpd.conf >/dev/null <<EOF
[global]

[lac ${VPN_CONNECTION_NAME}]
lns = ${VPN_SERVER_IP}
ppp debug = no
pppoptfile = ${PPP_OPTIONS_FILE}
length bit = yes
EOF

log "Configuring PPP"

sudo tee "${PPP_OPTIONS_FILE}" >/dev/null <<EOF
ipcp-accept-local
ipcp-accept-remote

refuse-eap
refuse-pap
refuse-chap
refuse-mschap

noauth

mtu ${VPN_PPP_MTU}
mru ${VPN_PPP_MRU}

name "${VPN_USERNAME}"
password "${VPN_PASSWORD}"
EOF

sudo chmod 600 "${PPP_OPTIONS_FILE}"

log "Starting IPsec"

sudo ipsec restart
sleep "${VPN_IPSEC_START_DELAY_SEC}"

log "Connecting IPsec"

if ! sudo ipsec up "${VPN_CONNECTION_NAME}"; then
    echo "IPsec connection failed." >&2
    dump_diagnostics
    exit 1
fi

if ! sudo ip xfrm state | grep -q 'proto esp'; then
    echo "IPsec connected, but no ESP XFRM state was created." >&2
    dump_diagnostics
    exit 1
fi

log "IPsec connected"

log "Restarting xl2tpd"

sudo systemctl restart xl2tpd
sleep "${VPN_L2TP_START_DELAY_SEC}"

if ! sudo systemctl is-active --quiet xl2tpd; then
    echo "xl2tpd failed to start." >&2
    dump_diagnostics
    exit 1
fi

if [[ ! -e /var/run/xl2tpd/l2tp-control ]]; then
    echo "xl2tpd control socket was not created." >&2
    dump_diagnostics
    exit 1
fi

log "Connecting L2TP"

echo "c ${VPN_CONNECTION_NAME}" |
    sudo tee /var/run/xl2tpd/l2tp-control >/dev/null

log "Waiting for ${VPN_PPP_INTERFACE}"

ppp_connected=false

for ((i = 0; i < VPN_CONNECT_TIMEOUT_SEC; i++)); do
    if ip -4 addr show dev "${VPN_PPP_INTERFACE}" 2>/dev/null |
        grep -q 'inet '; then

        ppp_connected=true
        break
    fi

    sleep 1
done

if [[ "${ppp_connected}" != true ]]; then
    echo "PPP connection timed out after ${VPN_CONNECT_TIMEOUT_SEC}s." >&2
    dump_diagnostics
    exit 1
fi

log "PPP connected"

ip -4 addr show dev "${VPN_PPP_INTERFACE}"

if [[ -n "${VPN_REMOTE_NETWORKS}" ]]; then
    log "Configuring VPN routes"

    for network in ${VPN_REMOTE_NETWORKS}; do
        log "Adding route: ${network} via ${VPN_PPP_INTERFACE}"

        sudo ip route replace \
            "${network}" \
            dev "${VPN_PPP_INTERFACE}"
    done
fi

log "Checking route to ${VPN_CHECK_HOST_IP}"

ip route get "${VPN_CHECK_HOST_IP}"

log "Checking connectivity to ${VPN_CHECK_HOST_IP}"

vpn_reachable=false

for ((i = 0; i < VPN_PING_TIMEOUT_SEC; i++)); do
    if ping \
        -c 1 \
        -W 1 \
        "${VPN_CHECK_HOST_IP}" \
        >/dev/null 2>&1; then

        vpn_reachable=true
        break
    fi

    sleep 1
done

if [[ "${vpn_reachable}" != true ]]; then
    echo \
        "VPN connectivity check failed: ${VPN_CHECK_HOST_IP} did not respond within ${VPN_PING_TIMEOUT_SEC}s." \
        >&2

    dump_diagnostics
    exit 1
fi

log "VPN connected successfully"
log "Connectivity check succeeded: ${VPN_CHECK_HOST_IP}"
