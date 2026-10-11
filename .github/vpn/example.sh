#!/usr/bin/env bash

set -Eeuo pipefail

: "${VPN_OUTPUT_ARTIFACT_DIR:?VPN_OUTPUT_ARTIFACT_DIR is required}"

REPORT_FILE="${VPN_OUTPUT_ARTIFACT_DIR}/vpn-context.html"

cat > "${REPORT_FILE}" <<EOF
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>VPN Context Report</title>
  <style>
    body {
      font-family: sans-serif;
      max-width: 960px;
      margin: 40px auto;
      padding: 0 24px;
      line-height: 1.6;
    }

    table {
      border-collapse: collapse;
      width: 100%;
    }

    th,
    td {
      border: 1px solid #ccc;
      padding: 8px 12px;
      text-align: left;
    }

    th {
      width: 40%;
      background: #f5f5f5;
    }

    code {
      font-family: monospace;
    }
  </style>
</head>
<body>
  <h1>VPN Context Report</h1>

  <p>
    Your VPN configuration looks good.
    Set the workflow entrypoint to the script you want to run inside
    the VPN context.
  </p>

  <h2>VPN context</h2>

  <table>
      <tr>
        <th>VPN_CONTEXT_ACTIVE</th>
        <td><code>${VPN_CONTEXT_ACTIVE:-}</code></td>
      </tr>
      <tr>
        <th>VPN_CONTEXT_INTERFACE</th>
        <td><code>${VPN_CONTEXT_INTERFACE:-}</code></td>
      </tr>
      <tr>
        <th>VPN_CONTEXT_LOCAL_IP</th>
        <td><code>${VPN_CONTEXT_LOCAL_IP:-}</code></td>
      </tr>
      <tr>
        <th>VPN_CONTEXT_PEER_IP</th>
        <td><code>${VPN_CONTEXT_PEER_IP:-}</code></td>
      </tr>
      <tr>
        <th>VPN_CONTEXT_CHECK_HOST_IP</th>
        <td><code>${VPN_CONTEXT_CHECK_HOST_IP:-}</code></td>
      </tr>
      <tr>
        <th>VPN_OUTPUT_ARTIFACT_DIR</th>
        <td><code>${VPN_OUTPUT_ARTIFACT_DIR}</code></td>
      </tr>
    </tbody>
  </table>

  <p>Enjoy!</p>
</body>
</html>
EOF

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
echo "Artifact created:"
echo "  ${REPORT_FILE}"
echo
echo "VPN context:"
printf '  %-32s %s\n' "VPN_CONTEXT_ACTIVE" "${VPN_CONTEXT_ACTIVE:-}"
printf '  %-32s %s\n' "VPN_CONTEXT_INTERFACE" "${VPN_CONTEXT_INTERFACE:-}"
printf '  %-32s %s\n' "VPN_CONTEXT_LOCAL_IP" "${VPN_CONTEXT_LOCAL_IP:-}"
printf '  %-32s %s\n' "VPN_CONTEXT_PEER_IP" "${VPN_CONTEXT_PEER_IP:-}"
printf '  %-32s %s\n' "VPN_CONTEXT_SERVER_IP" "${VPN_CONTEXT_SERVER_IP:-}"
printf '  %-32s %s\n' "VPN_CONTEXT_CHECK_HOST_IP" "${VPN_CONTEXT_CHECK_HOST_IP:-}"
printf '  %-32s %s\n' "VPN_OUTPUT_ARTIFACT_DIR" "${VPN_OUTPUT_ARTIFACT_DIR}"
echo
echo "Enjoy!"

echo "--- VPN interface ---"

ip -4 addr show dev "${VPN_CONTEXT_INTERFACE}"

echo
echo "--- Route to check host ---"

ip route get "${VPN_CONTEXT_CHECK_HOST_IP}"
