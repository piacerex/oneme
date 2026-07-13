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

顔写真の元画像はブラウザ内だけで扱います。顔写真由来の派生テクスチャをGLB/FBXへ含める場合は、画面上で明示的な同意が必要です。

## FBXエクスポート

サーバー側FBX変換にはAssimpが必要です。実行ファイルがPATHにない場合は、`ONEME_ASSIMP_BIN`で指定します。

```bash
ONEME_ASSIMP_BIN=/usr/bin/assimp mix phx.server
```

`POST /api/export-jobs` に `format: "fbx"` とアバター設定を送ると、生成済みモデルURLを返します。GLBはブラウザのGLTFExporterから直接ダウンロードできます。

## 検証

```bash
cd apps/oneme
mix test
mix assets.build
```

詳細な実装順と本番移行項目は、ルートの `ROADMAP.md` を参照してください。
