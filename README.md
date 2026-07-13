# oneme

Phoenix/LiveViewで作る3Dアバタービルダーです。

## 起動

```bash
cd apps/oneme
eval "$(mise activate bash)"
mix setup
mix phx.server
```

`http://localhost:4000/` を開くと、Three.jsの回転プレビュー、パーツ編集、顔写真の輪郭マスク、顔面テクスチャマッピングを確認できます。

顔写真の元画像はブラウザ内だけで扱います。顔写真由来の派生テクスチャをGLB/FBX/VRMへ含める場合は、画面上で明示的な同意が必要です。

顔写真の輪郭マスク済みCanvasから肌色・髪色をブラウザ内で推定し、LiveViewの色設定へ反映します。推定値も元写真や画像URLとして保存しません。

サーバー側の一時解析契約として`POST /api/face-analysis-jobs`、`GET /api/face-analysis-jobs/:id`、`POST /api/avatars/from-face-analysis`を提供します。入力は派生メタデータだけに限定し、ジョブは15分で期限切れになります。

## サーバー側エクスポート

サーバー側FBX変換にはAssimpが必要です。実行ファイルがPATHにない場合は、`ONEME_ASSIMP_BIN`で指定します。

```bash
ONEME_ASSIMP_BIN=/usr/bin/assimp mix phx.server
```

`POST /api/export-jobs` に `format: "fbx"` または `format: "vrm"` とアバター設定を送ると、生成済みモデルURLを返します。GLBはブラウザのGLTFExporterから直接ダウンロードできます。

VRMは実メッシュGLBへVRM 1.0のhumanoidノード、skin（JOINTS/WEIGHTS）、表情モーフ、`VRMC_springBone`を付与した`.vrm`として出力します。外部VRMビューア、Unity、Webランタイムでの読み込み互換性は引き続き検証工程です。

`GET /api/health` はPhoenixとPostgreSQLの稼働状態を返します。エクスポート要求、公開アバターの読み取り、公開・エクスポート完了は利用イベントまたは監査ログへ記録します。これらの記録には元写真や顔テクスチャ本体を含めません。

APIは開発時には匿名互換で動作します。本番では`ONEME_AUTH_REQUIRED=true`を設定し、`ONEME_AUTH_BOOTSTRAP_TOKEN`付きで`POST /api/auth/bootstrap`を一度だけ実行してowner用APIキーを発行します。APIキーはハッシュのみ保存され、owner/adminは`/api/auth/api-keys`で追加キーを作成・失効できます。`Authorization: Bearer ...`または`x-oneme-api-key`を使います。

`GET /api/usage`はadmin以上のチーム利用量を日次カウンタから返します。APIはAPIキーまたはIP単位で固定窓レート制限を行い、`ONEME_RATE_LIMIT_PER_MINUTE`で上限を変更できます。`x-ratelimit-*`と超過時の`retry-after`を返します。

`GET /api/billing`はチームのプラン、契約期間、期間内利用量、残り上限を返します。`PATCH /api/billing/subscription`で管理者が契約状態を更新でき、ownerは`POST /api/billing/plans`でprovider-neutralなプラン定義を追加できます。決済代行会社、請求書、カード情報はまだ接続していません。

admin以上は`/api/webhooks`でWebhookを登録できます。秘密値は暗号化保存され、作成時のレスポンスで一度だけ返されます。`/api/webhooks/:id/test`は外部HTTP送信前の署名済みqueued deliveryを作成し、`deliver=true`または再試行APIで非同期workerへ渡します。workerは再起動時にDBのqueued deliveryを回収します。`/api/audit-logs`と`/api/audit-logs/retention`で監査記録の参照・保持期限削除を行います。

`GET /api/assets/integrity`はadmin以上がアセットの参照元、ライセンス契約、審査状態を確認する管理APIです。`POST /api/assets/:asset_key/inspect`または`POST /api/assets/inspect`で実ファイルのSHA-256、サイズ、GLB/FBX/PNG/JPEGのヘッダーを検査し、結果を台帳へ保存します。現在のデモアセットは`procedural://`契約として検査されます。

`GET /api/monitoring/cdn`は環境変数`ONEME_CDN_URLS`にカンマ区切りで設定したHTTPSエンドポイントをHEADリクエストで検査します。`ONEME_CDN_ALLOWED_HOSTS`を設定すると対象ホストを制限でき、`ONEME_CDN_CHECK_INTERVAL_MS`で周期チェック間隔を変更できます。

利用規約とプライバシーポリシーの技術初稿は`docs/legal/terms.md`と`docs/legal/privacy.md`にあります。公開前の法務レビューで、事業者情報、提供地域、料金、保持期間、問い合わせ窓口を確定してください。

`POST /api/generation-jobs` は現在のアバター設定から3つの候補を作り、`POST /api/generation-jobs/:id/feedback` で採用・却下を記録します。現段階のプロバイダーは既存パーツを推薦するローカル実装で、画像生成サービスへ差し替えられるジョブ境界を使います。

生成済み候補の再生成は`POST /api/generation-jobs/:id/regenerate`、失敗ジョブの再試行は`POST /api/generation-jobs/:id/retry`です。

`GET /api/parts` はDB上のパーツ台帳と、原点・スケール・ライセンス情報を返します。アバターは`POST /api/avatars`と`PATCH /api/avatars/:id`で保存・更新できます。

公開アバターのモデルは`GET /api/avatars/:id/model?format=glb`、明示的な生成は`POST /api/avatars/:id/exports`で取得できます。エクスポートジョブは同じ設定と派生テクスチャの入力をキャッシュし、失敗ジョブは`POST /api/export-jobs/:id/retry`で再実行できます。

## Widget

`http://localhost:4000/widget-example.html` でiframe埋め込み例を確認できます。Widgetは保存完了時に親ページへ、指定した親オリジンへ `avatar_saved` メッセージを送ります。

本番でWidget認証を有効にする場合は`ONEME_WIDGET_APP_ID`と`ONEME_WIDGET_API_KEY`を設定し、URLへ`app_id`、`api_key`、`parent_origin`を渡します。`avatar_id`を追加すると保存済みアバターから編集を再開できます。

## Web SDK

`packages/sdk-web` にパーツ、アバター、候補生成、公開モデル、エクスポートジョブを扱うクライアントとThree.js表示ヘルパーを用意しています。`http://localhost:4000/sdk-example.html?avatar_id=...` でも公開レスポンスを確認できます。`packages/sdk-unity`はモデルAPIからGLB/VRMバイナリを取得し、glTFastでSceneへ展開するUnity向けSDKです。

## 検証

```bash
cd apps/oneme
mix test
mix assets.build
```

詳細な実装順と本番移行項目は、ルートの `ROADMAP.md` を参照してください。
