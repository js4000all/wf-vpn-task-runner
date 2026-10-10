# wf-vpn-connection
VPN接続をして所定の処理を行うGitHub workflowの雛形

## VPN workflow configuration

VPN 接続 workflow では、GitHub Actions の Variables / Secrets と `.github/scripts/vpn-defaults.sh` の既定値を組み合わせて設定します。

設定値は次の3種類に分類します。

- 実行環境ごとに異なる値: GitHub Variables での指定必須
- 機密情報: GitHub Secrets での指定必須
- VPN サーバ仕様・運用上の既定値: `vpn-defaults.sh` に定義し、必要に応じて GitHub Variables で上書き可能

### Required variables

以下は GitHub Actions の Repository Variables に設定する必要があります。

| Name | Required | Override | Description |
| --- | --- | --- | --- |
| `VPN_SERVER_IP` | Yes | - | VPN サーバの IPv4 アドレス。IKE の接続先および `rightid` として使用します。 |
| `VPN_USERNAME` | Yes | - | PPP / MS-CHAPv2 認証で使用する VPN ユーザー名です。 |
| `VPN_CHECK_HOST_IP` | Yes | - | VPN 接続確認に使用する VPC 内の代表 VM の IPv4 アドレスです。PPP 接続後、このホストへの ping 成功をもって VPN 接続成功と判定します。 |

### Required secrets

以下は GitHub Actions の Repository Secrets に設定する必要があります。

| Name | Required | Description |
| --- | --- | --- |
| `VPN_PSK` | Yes | IKEv1 / IPsec で使用する Pre-Shared Key です。 |
| `VPN_PASSWORD` | Yes | PPP / MS-CHAPv2 認証で使用する VPN パスワードです。 |

### VPN implementation settings

以下は `.github/scripts/vpn-defaults.sh` に既定値があります。

通常は変更不要ですが、接続先 VPN サーバの仕様が異なる場合は、同名の GitHub Repository Variable を設定することで上書きできます。

| Name | Required | Default | Override | Description |
| --- | --- | --- | --- | --- |
| `VPN_CONNECTION_NAME` | No | `l2tp-vpn` | Yes | strongSwan および xl2tpd 内で使用する接続名です。 |
| `VPN_IKE_VERSION` | No | `ikev1` | Yes | IKE バージョンです。 |
| `VPN_IKE_PROPOSAL` | No | `3des-sha1-modp1024!` | Yes | IKE Phase 1 の暗号スイートです。 |
| `VPN_ESP_PROPOSAL` | No | `aes256-sha1!` | Yes | IPsec ESP の暗号スイートです。 |
| `VPN_IKE_LIFETIME` | No | `8h` | Yes | IKE SA の lifetime です。 |
| `VPN_L2TP_PORT` | No | `1701` | Yes | L2TP の UDP ポート番号です。 |
| `VPN_PPP_MTU` | No | `1280` | Yes | PPP インターフェースの MTU です。 |
| `VPN_PPP_MRU` | No | `1280` | Yes | PPP インターフェースの MRU です。 |
| `VPN_PPP_INTERFACE` | No | `ppp0` | Yes | VPN 接続時に生成される PPP インターフェース名です。 |

上記の既定値は、現在利用している L2TP/IPsec VPN サーバで実接続確認済みの値を基準にしています。

特に `VPN_IKE_PROPOSAL`、`VPN_ESP_PROPOSAL`、`VPN_IKE_LIFETIME` は VPN サーバ側の仕様に依存するため、別の VPN サーバを使用する場合は必要に応じて変更してください。

### Operational settings

以下は接続処理の待機時間やタイムアウトを制御します。

通常は変更不要ですが、GitHub Repository Variables から上書きできます。

| Name | Required | Default | Override | Description |
| --- | --- | --- | --- | --- |
| `VPN_IPSEC_START_DELAY_SEC` | No | `1` | Yes | strongSwan 再起動後、IPsec 接続を開始するまでの待機秒数です。 |
| `VPN_L2TP_START_DELAY_SEC` | No | `1` | Yes | xl2tpd 再起動後、L2TP 接続を開始するまでの待機秒数です。 |
| `VPN_CONNECT_TIMEOUT_SEC` | No | `20` | Yes | PPP インターフェース確立を待機する最大秒数です。 |
| `VPN_PING_TIMEOUT_SEC` | No | `20` | Yes | `VPN_CHECK_HOST_IP` への疎通確認を待機する最大秒数です。 |
| `VPN_DISCONNECT_TIMEOUT_SEC` | No | `5` | Yes | VPN 切断時に PPP インターフェースの消滅を待機する最大秒数です。 |

### Configuration precedence

設定値の優先順位は次の通りです。

1. GitHub Actions の Repository Variables / Secrets
2. `.github/scripts/vpn-defaults.sh` の既定値

workflow では上書き可能な Variables もすべて環境変数として参照します。

未定義の Repository Variable は空文字列として渡されますが、`vpn-defaults.sh` では以下の形式で既定値を適用します。

```bash
VPN_IKE_VERSION="${VPN_IKE_VERSION:-ikev1}"
```

そのため、任意設定の Variable を GitHub 側に登録していない場合は、自動的に `vpn-defaults.sh` の既定値が使用されます。

一方、`VPN_SERVER_IP`、`VPN_USERNAME`、`VPN_CHECK_HOST_IP`、`VPN_PSK`、`VPN_PASSWORD` には有効な既定値を持たせません。未設定の場合、`vpn-start.sh` が接続開始前にエラー終了します。

## HOW TO USE

TBD

### Connection success criteria

`vpn-start.sh` は、以下をすべて満たした場合のみ正常終了します。

1. IKE / IPsec SA が確立している
2. ESP の XFRM state が作成されている
3. L2TP セッションが確立している
4. PPP インターフェースが作成され、IPv4 アドレスが割り当てられている
5. `VPN_CHECK_HOST_IP` への ping が成功している

そのため、`with-vpn.sh` から実行されるコマンドは、VPC 内への疎通が確認済みの VPN 接続コンテキストで開始されます。
