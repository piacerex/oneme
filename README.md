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

## サーバー側エクスポート

サーバー側FBX変換にはAssimpが必要です。実行ファイルがPATHにない場合は、`ONEME_ASSIMP_BIN`で指定します。

```bash
ONEME_ASSIMP_BIN=/usr/bin/assimp mix phx.server
```

`POST /api/export-jobs` に `format: "fbx"` または `format: "vrm"` とアバター設定を送ると、生成済みモデルURLを返します。GLBはブラウザのGLTFExporterから直接ダウンロードできます。

VRMは実メッシュGLBへonemeのメタデータ契約を付与した`.vrm`として出力します。現段階では完全なhumanoidボーンリグや表情・揺れ物の実装ではなく、VRMリグ対応は次の拡張工程です。

`GET /api/health` はPhoenixとPostgreSQLの稼働状態を返します。エクスポート要求、公開アバターの読み取り、公開・エクスポート完了は利用イベントまたは監査ログへ記録します。これらの記録には元写真や顔テクスチャ本体を含めません。

`POST /api/generation-jobs` は現在のアバター設定から3つの候補を作り、`POST /api/generation-jobs/:id/feedback` で採用・却下を記録します。現段階のプロバイダーは既存パーツを推薦するローカル実装で、画像生成サービスへ差し替えられるジョブ境界を使います。

`GET /api/parts` はDB上のパーツ台帳と、原点・スケール・ライセンス情報を返します。アバターは`POST /api/avatars`と`PATCH /api/avatars/:id`で保存・更新できます。

公開アバターのモデルは`GET /api/avatars/:id/model?format=glb`、明示的な生成は`POST /api/avatars/:id/exports`で取得できます。エクスポートジョブは同じ設定と派生テクスチャの入力をキャッシュし、失敗ジョブは`POST /api/export-jobs/:id/retry`で再実行できます。

## Widget

`http://localhost:4000/widget-example.html` でiframe埋め込み例を確認できます。Widgetは保存完了時に親ページへ、指定した親オリジンへ `avatar_saved` メッセージを送ります。

## Web SDK

`packages/sdk-web` に公開アバター、設定JSON、エクスポートジョブを取得する小さなクライアントを用意しています。`http://localhost:4000/sdk-example.html?avatar_id=...` でも公開レスポンスを確認できます。

## 検証

```bash
cd apps/oneme
mix test
mix assets.build
```

詳細な実装順と本番移行項目は、ルートの `ROADMAP.md` を参照してください。
