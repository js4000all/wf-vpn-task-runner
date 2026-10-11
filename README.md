# wf-vpn-task-runner

L2TP/IPsec による VPN 接続を確立し、その接続コンテキスト内で所定の処理を実行するための GitHub Actions ベースの実行基盤です。
基盤側で VPN 接続の確立・疎通確認・切断を管理し、接続確立後に利用者が指定したスクリプトを実行します。

利用者は VPN 接続処理の詳細を意識せず、VPN 接続後に実行したい処理の実装に集中できます。

## Getting started

このリポジトリを利用する場合は、まずリポジトリを複製するか Fork します。
その後、下記の要領で最小限の要素を追加します。

- Variables / Secrets の設定
- VPCに接続した状態で実行したいスクリプト
- そのスクリプトを起動するための薄いwrapper workflow

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

それぞれの詳細は[後段](#vpn-workflow-configuration)を参照してください。
その他の VPN 設定値には既定値があり、必要な場合のみ Repository Variables で上書きできます。

### 2. VPN 接続を確認する

サンプルworkflowである[Run VPN task manually](.github/workflows/run-vpn-task-manual.yml)では、
VPN 接続後に[.github/vpn/example.sh](.github/vpn/example.sh)が実行されます。
このスクリプトは VPN コンテキストやルーティング情報をログ出力し、簡潔なHTMLレポートを[アーティファクト](#artifact-output)として出力します。

`workflow_dispatch` から workflow を実行し、正常終了することを確認してください。

### 3. 実行条件と処理を結びつける

処理本体は reusable workflow として分離されているため、いつ何を実行するかだけを薄い wrapper workflow として定義します。
例えば`.github/workflows/collect-metrics.yml`を作成し、実行条件を記述するとともに、`uses`で`./.github/workflows/vpn-task.yml`を実行するように定義します。実行したい処理は`vpn-task.yml`のinputsに指定します。

詳細は[後段](#wrapper-workflow)を参照してください。


## Wrapper workflow

本基盤では、実際の実行条件と実行対象を薄い wrapper workflow で定義します。

VPN 接続処理そのものは reusable workflow である `.github/workflows/vpn-task.yml` に集約されているため、wrapper workflow では主に以下を指定します。

- いつ実行するか
- VPN 接続後に何を実行するか
- 必要に応じて artifact の名前や保持期間

最小構成は次の通りです。

```yaml
name: Run VPN task

on:
  workflow_dispatch:

jobs:
  run:
    uses: ./.github/workflows/vpn-task.yml
    with:
      entrypoint: .github/vpn/example.sh
    secrets: inherit
```

定期実行が必要なら、wrapper workflow 側に `schedule` を定義します。

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
      output-artifact-name: vm-metrics
    secrets: inherit
```

このように、VPN 接続基盤を変更せず、処理ごとに異なるスケジュールと entrypoint を Git 管理できます。

### Inputs

`vpn-task.yml` は以下の inputs を受け取ります。

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `entrypoint` | Yes | - | VPN 接続確立後に実行するスクリプトのパスです。リポジトリルートからの相対パスで指定します。 |
| `output-artifact-name` | No | `vpn-task` | `VPN_OUTPUT_ARTIFACT_DIR` に生成されたファイルを保存する GitHub Actions artifact の名前です。 |
| `retention-days` | No | workflow 定義値 | artifact の保持日数です。用途に応じて wrapper workflow から変更できます。 |

### Multiple tasks in one repository

実行タイミングの異なる複数の処理を、同じリポジトリ内で管理することもできます。

例えば、

```text
.github/
  workflows/
    vpn-task.yml
    collect-hourly.yml
    nightly-maintenance.yml
    weekly-report.yml

scripts/
  collect-metrics.sh
  nightly-maintenance.sh
  weekly-report.sh
```

のように配置し、それぞれの wrapper workflow で異なる `entrypoint` を指定します。これにより、VPN 接続設定は共通化したまま、スケジュールと実行処理だけを独立して管理できます。


## Artifact input/output

### 入力

wrapper workflowで`input-artifact-name` inputを指定すると、既に同名のアーティファクトが存在すると見なしてダウンロードします。
entrypointスクリプトには、ダウンロード先のディレクトリパスとして`VPN_INPUT_ARTIFACT_DIR`が渡されます。

```bash
ls -la "${VPN_INPUT_ARTIFACT_DIR}"
```

### 出力

VPN 接続コンテキスト内で実行される entrypoint スクリプトには、成果物の出力先ディレクトリパスとして `VPN_OUTPUT_ARTIFACT_DIR` が渡されます。

entrypoint スクリプトは、GitHub Actions の artifact 機能を直接意識する必要はありません。保存したいファイルを `VPN_OUTPUT_ARTIFACT_DIR` 配下に出力するだけで、workflow 終了時に自動的に回収されます。

```bash
#!/usr/bin/env bash

set -Eeuo pipefail

: "${VPN_OUTPUT_ARTIFACT_DIR:?VPN_OUTPUT_ARTIFACT_DIR is required}"

ssh monitor@172.27.1.10 'df -h' \
  > "${VPN_OUTPUT_ARTIFACT_DIR}/disk-usage.txt"

ssh monitor@172.27.1.10 'free -m' \
  > "${VPN_OUTPUT_ARTIFACT_DIR}/memory.txt"
```

entrypoint が正常終了しなかった場合でも、それまでに `VPN_OUTPUT_ARTIFACT_DIR` に生成されたファイルは回収対象になります。

`VPN_OUTPUT_ARTIFACT_DIR` 内にファイルが存在しない場合は artifact は作成されません。そのため、成果物を必要としない処理でも特別な設定は不要です。

artifact の名前は wrapper workflow から `output-artifact-name` input で指定できます(省略した場合は `vpn-task`)。


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
| `VPN_INPUT_ARTIFACT_DIR` | 既存artifact のダウンロード先ディレクトリパス |
| `VPN_OUTPUT_ARTIFACT_DIR` | artifact として回収させたいファイルの出力先ディレクトリパス |

これらを利用することで、entrypoint スクリプトは VPN の確立処理や GitHub Actions の artifact 実装を意識せず、VPC 内で実行したい処理と成果物の生成に集中できます。


### 例

```yaml
jobs:
  prepare:
    runs-on: ubuntu-latest

    steps:
      - name: Prepare target list
        run: |
          mkdir -p input
          ./scripts/build-target-list.sh > input/targets.json

      - name: Upload input
        uses: actions/upload-artifact@v7
        with:
          name: vm-metrics-input
          path: input

  vpn-task:
    needs: prepare
    uses: ./.github/workflows/vpn-task.yml
    with:
      entrypoint: ./scripts/collect-metrics.sh
      input-artifact-name: vm-metrics-input
      artifact-name: vm-metrics
    secrets: inherit
```


## VPN workflow configuration

VPN 接続 workflow では、GitHub Actions の Variables / Secrets と `.github/scripts/vpn-defaults.sh` の既定値を組み合わせて設定します。

設定値は次の3種類に分類します。

- 実行環境ごとに異なる値: GitHub Variables での指定必須
- 機密情報: GitHub Secrets での指定必須
- VPN サーバ仕様・運用上の既定値: `vpn-defaults.sh` に定義し、必要に応じて GitHub Variables で上書き可能

### Required variables

以下は GitHub Actions の Repository Variables に設定する必要があります。

| Name | Description |
| --- | --- |
| `VPN_SERVER_IP` | VPN サーバの IPv4 アドレス。IKE の接続先および `rightid` として使用します。 |
| `VPN_USERNAME` | PPP / MS-CHAPv2 認証で使用する VPN ユーザー名です。 |
| `VPN_REMOTE_NETWORKS` | VPCのネットワークアドレスです。`172.28.0.0/16`など。 |
| `VPN_CHECK_HOST_IP` | VPN 接続確認に使用する VPC 内の代表 VM の IPv4 アドレスです。PPP 接続後、このホストへの ping 成功をもって VPN 接続成功と判定します。 |

### Required secrets

以下は GitHub Actions の Repository Secrets に設定する必要があります。

| Name | Description |
| --- | --- |
| `VPN_PSK` | IKEv1 / IPsec で使用する Pre-Shared Key です。 |
| `VPN_PASSWORD` | PPP / MS-CHAPv2 認証で使用する VPN パスワードです。 |

### VPN implementation settings

以下は `.github/scripts/vpn-defaults.sh` に既定値があります。
同名の GitHub Repository Variable を設定することで上書きできます。

| Name | Default | Override | Description |
| --- | --- | --- | --- |
| `VPN_CONNECTION_NAME` | `l2tp-vpn` | Yes | strongSwan および xl2tpd 内で使用する接続名です。 |
| `VPN_IKE_VERSION` | `ikev1` | Yes | IKE バージョンです。 |
| `VPN_IKE_PROPOSAL` |`3des-sha1-modp1024!` | Yes | IKE Phase 1 の暗号スイートです。 |
| `VPN_ESP_PROPOSAL` |`aes256-sha1!` | Yes | IPsec ESP の暗号スイートです。 |
| `VPN_IKE_LIFETIME` |`8h` | Yes | IKE SA の lifetime です。 |
| `VPN_L2TP_PORT` | `1701` | Yes | L2TP の UDP ポート番号です。 |
| `VPN_PPP_MTU` | `1280` | Yes | PPP インターフェースの MTU です。 |
| `VPN_PPP_MRU` | `1280` | Yes | PPP インターフェースの MRU です。 |
| `VPN_PPP_INTERFACE` | `ppp0` | Yes | VPN 接続時に生成される PPP インターフェース名です。 |

既定値は、さくらのクラウドの VPN ルータで実接続を確認した構成を基準にしています。接続先 VPN サーバに応じて設定を変更してください。
特に `VPN_IKE_PROPOSAL`、`VPN_ESP_PROPOSAL`、`VPN_IKE_LIFETIME` は VPN サーバ側の仕様に依存することが多いので、他の VPN サーバを利用する場合は事前に対応値を確認してください。

### Operational settings

以下は接続処理の待機時間やタイムアウトを制御します。

通常は変更不要ですが、GitHub Repository Variables から上書きできます。

| Name | Default | Override | Description |
| --- | --- | --- | --- |
| `VPN_IPSEC_START_DELAY_SEC` | `1` | Yes | strongSwan 再起動後、IPsec 接続を開始するまでの待機秒数です。 |
| `VPN_L2TP_START_DELAY_SEC` | `1` | Yes | xl2tpd 再起動後、L2TP 接続を開始するまでの待機秒数です。 |
| `VPN_CONNECT_TIMEOUT_SEC` | `20` | Yes | PPP インターフェース確立を待機する最大秒数です。 |
| `VPN_PING_TIMEOUT_SEC` | `20` | Yes | `VPN_CHECK_HOST_IP` への疎通確認を待機する最大秒数です。 |
| `VPN_DISCONNECT_TIMEOUT_SEC` | `5` | Yes | VPN 切断時に PPP インターフェースの消滅を待機する最大秒数です。 |

### Configuration precedence

設定値の優先順位は次の通りです。

1. GitHub Actions の Repository Variables / Secrets
2. `.github/scripts/vpn-defaults.sh` の既定値

workflow では上書き可能な Variables もすべて環境変数として参照します。

未定義の Repository Variable は空文字列として渡されますが、`vpn-defaults.sh` で以下の形式で既定値を適用します。

```bash
VPN_IKE_VERSION="${VPN_IKE_VERSION:-ikev1}"
```

これにより、任意設定の Variable を GitHub 側に登録していない場合は、自動的に `vpn-defaults.sh` の既定値が使用されます。

一方、`VPN_SERVER_IP`、`VPN_USERNAME`、`VPN_CHECK_HOST_IP`、`VPN_PSK`、`VPN_PASSWORD` には有効な既定値を持たせません。未設定の場合、`vpn-start.sh` が接続開始前にエラー終了します。

### Connection success criteria

`vpn-start.sh` は、以下をすべて満たした場合のみ正常終了します。

1. IKE / IPsec SA が確立している
2. ESP の XFRM state が作成されている
3. L2TP セッションが確立している
4. PPP インターフェースが作成され、IPv4 アドレスが割り当てられている
5. `VPN_CHECK_HOST_IP` への ping が成功している

そのため、`with-vpn.sh` から実行されるコマンドは、VPC 内への疎通が確認済みの VPN 接続コンテキストで開始されます。
