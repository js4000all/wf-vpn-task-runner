# wf-vpn-task-runner

L2TP/IPsec による VPN 接続を確立し、その接続コンテキスト内で所定の処理を実行するための GitHub Actions ベースの実行基盤です。
基盤側で VPN 接続の確立・疎通確認・切断を管理し、接続確立後に利用者が指定したスクリプトを実行します。

利用者は VPN 接続処理の詳細を意識せず、VPN 接続後に実行したい処理の実装に集中できます。

## Getting started

このリポジトリを利用する場合は、リポジトリを複製するか Fork して開始します。

本基盤はそのまま再利用できるように構成しているので、通常は既存の workflow や `.github/scripts/` 配下のファイルを変更する必要はありません。

### 1. Repository Variables / Secrets を設定する

最低限、以下を設定します。

**Variables**

- `VPN_SERVER_IP`
- `VPN_USERNAME`
- `VPN_REMOTE_NETWORKS`
- `VPN_CHECK_HOST_IP`

**Secrets**

- `VPN_PSK`
- `VPN_PASSWORD`

それぞれの詳細は後段を参照してください。
その他の VPN 設定値には既定値があり、必要な場合のみ Repository Variables で上書きできます。

### 2. VPN 接続を確認する

初期状態では、VPN 接続後に `.github/vpn/example.sh` が実行されます。このスクリプトでは VPN コンテキストやルーティング、代表 VM への疎通を確認できます(実際には代表VMへの疎通完了をもってVPN接続完了と判定するので、この時点では必ず疎通します)。

`workflow_dispatch` から workflow を実行し、正常終了することを確認してください。

### 3. 実行条件と処理を結びつける

処理本体は reusable workflow として分離されているため、いつ何を実行するかのみ、薄い wrapper workflow として定義します。
例えば、毎時でメトリクス収集するならこうします。

```yaml
name: Collect VM metrics

on:
  workflow_dispatch:
  schedule:
    - cron: '0 * * * *'

jobs:
  run:
    uses: ./.github/workflows/vpn-task.yml
    with:
      entrypoint: ./scripts/collect-metrics.sh
    secrets: inherit
```

実行したいスクリプトのパスは、`entrypoint`として処理本体に引き渡します。

Forkして利用する場合も、既存の VPN 基盤ファイルを変更せず、Variables / Secrets、実行スクリプト、wrapper workflow の追加だけでカスタマイズすることを推奨します。これにより upstream からの変更を取り込みやすく、不要な差分や conflict を減らせます。


## Artifact output

VPN 接続コンテキスト内で実行される entrypoint スクリプトには、成果物の出力先ディレクトリパスとして `VPN_ARTIFACT_DIR` が渡されます。

entrypoint スクリプトは、GitHub Actions の artifact 機能を直接意識する必要はありません。保存したいファイルを `VPN_ARTIFACT_DIR` 配下に出力するだけで、workflow 終了時に自動的に回収されます。

例:

```bash
#!/usr/bin/env bash

set -Eeuo pipefail

: "${VPN_ARTIFACT_DIR:?VPN_ARTIFACT_DIR is required}"

ssh monitor@172.27.1.10 'df -h' \
  > "${VPN_ARTIFACT_DIR}/disk-usage.txt"

ssh monitor@172.27.1.10 'free -m' \
  > "${VPN_ARTIFACT_DIR}/memory.txt"
```

entrypoint が正常終了しなかった場合でも、それまでに `VPN_ARTIFACT_DIR` に生成されたファイルは回収対象になります。

`VPN_ARTIFACT_DIR` 内にファイルが存在しない場合は artifact は作成されません。そのため、成果物を必要としない処理でも特別な設定は不要です。

artifact の名前は wrapper workflow から `artifact-name` input で指定できます(省略した場合は `vpn-task`)。

```yaml
jobs:
  run:
    uses: ./.github/workflows/vpn-task.yml
    with:
      entrypoint: .github/vpn/collect-metrics.sh
      artifact-name: vm-metrics
    secrets: inherit
```

### Available VPN context

entrypoint スクリプトには、VPN 接続後の情報も環境変数として渡されます。

| Name | Description |
| --- | --- |
| `VPN_CONTEXT_ACTIVE` | VPN 接続コンテキスト内で実行されている場合は `true` |
| `VPN_CONTEXT_INTERFACE` | PPP インターフェース名 |
| `VPN_CONTEXT_LOCAL_IP` | PPP 接続で割り当てられたローカル IP アドレス |
| `VPN_CONTEXT_PEER_IP` | PPP peer の IP アドレス |
| `VPN_CONTEXT_SERVER_IP` | VPN サーバの IP アドレス |
| `VPN_CONTEXT_CHECK_HOST_IP` | VPN 接続確認に使用した VPC 内ホストの IP アドレス |
| `VPN_ARTIFACT_DIR` | artifact として回収させたいファイルの出力先ディレクトリパス |

これらを利用することで、entrypoint スクリプトは VPN の確立処理や GitHub Actions の artifact 実装を意識せず、VPC 内で実行したい処理と成果物の生成に集中できます。


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
| `VPN_REMOTE_NETWORKS` | Yes | - | VPCのネットワークアドレスです。`172.28.0.0/16`など。 |
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

### Connection success criteria

`vpn-start.sh` は、以下をすべて満たした場合のみ正常終了します。

1. IKE / IPsec SA が確立している
2. ESP の XFRM state が作成されている
3. L2TP セッションが確立している
4. PPP インターフェースが作成され、IPv4 アドレスが割り当てられている
5. `VPN_CHECK_HOST_IP` への ping が成功している

そのため、`with-vpn.sh` から実行されるコマンドは、VPC 内への疎通が確認済みの VPN 接続コンテキストで開始されます。
