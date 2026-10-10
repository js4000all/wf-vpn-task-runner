#!/usr/bin/env bash

set -Eeuo pipefail

echo
echo "============================================================"
echo " VPN connection is ready!"
echo "============================================================"
echo
echo "Your VPN configuration looks good."
echo
echo "Set the GitHub Actions variable VPN_ENTRYPOINT_SCRIPT"
echo "to the script you want to run inside the VPN context."
echo
echo "Enjoy!"
echo

echo "--- VPN context ---"

printf '%-32s %s\n' \
    "VPN_CONTEXT_ACTIVE" \
    "${VPN_CONTEXT_ACTIVE:-}"

printf '%-32s %s\n' \
    "VPN_CONTEXT_INTERFACE" \
    "${VPN_CONTEXT_INTERFACE:-}"

printf '%-32s %s\n' \
    "VPN_CONTEXT_LOCAL_IP" \
    "${VPN_CONTEXT_LOCAL_IP:-}"

printf '%-32s %s\n' \
    "VPN_CONTEXT_PEER_IP" \
    "${VPN_CONTEXT_PEER_IP:-}"

printf '%-32s %s\n' \
    "VPN_CONTEXT_SERVER_IP" \
    "${VPN_CONTEXT_SERVER_IP:-}"

printf '%-32s %s\n' \
    "VPN_CONTEXT_CHECK_HOST_IP" \
    "${VPN_CONTEXT_CHECK_HOST_IP:-}"

echo
echo "--- VPN interface ---"

ip -4 addr show dev "${VPN_CONTEXT_INTERFACE}"

echo
echo "--- Route to check host ---"

ip route get "${VPN_CONTEXT_CHECK_HOST_IP}"

echo
echo "--- Connectivity check ---"

ping \
    -c 3 \
    -W 1 \
    "${VPN_CONTEXT_CHECK_HOST_IP}"

echo
echo "VPN context is working correctly."
