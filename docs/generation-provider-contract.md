# 生成プロバイダー契約

## リクエスト

`ONEME_GENERATION_PROVIDER=http_json`を指定すると、Phoenixは
`ONEME_GENERATION_PROVIDER_URL`へHTTPS POSTする。開発時に限り、localhostへのHTTPを
`ONEME_GENERATION_ALLOW_INSECURE_HTTP=true`で許可できる。

```json
{
  "kind": "face_candidates",
  "avatarConfig": {
    "parts": {},
    "colors": {},
    "faceMorph": {},
    "faceAnalysis": {},
    "faceTexture": {}
  }
}
```

`avatarConfig`から元写真のdata URL、画像バイナリ、元写真フィールドは除外する。
APIキーは`ONEME_GENERATION_PROVIDER_API_KEY`からBearerトークンとして送信し、ログへ出さない。

## レスポンス

```json
{
  "provider": "image-provider",
  "moderation": {
    "provider": "moderation-provider",
    "status": "passed"
  },
  "usage": {
    "inputTokens": 120,
    "outputTokens": 80,
    "costCents": 7
  },
  "candidates": [
    {
      "id": "candidate-1",
      "label": "Studio",
      "style": "studio",
      "reason": "生成理由",
      "parts": {
        "face": "face.soft_01",
        "hair": "hair.short_01"
      },
      "imageUrl": "https://cdn.example.com/candidate-1.png"
    }
  ]
}
```

`candidates`は最大3件へ制限し、`parts`は既知のアバターパーツキーだけを取り込む。
`imageUrl`はHTTPS URLだけを保存する。`moderation.status`が`blocked`、`rejected`、
`failed`の場合は候補を拒否する。本番で審査を必須にする場合は
`ONEME_GENERATION_REQUIRE_MODERATION=true`を設定する。

`usage`の整数値は`inputTokens`、`outputTokens`、`costCents`だけを利用イベントへコピーする。
プロバイダーのレスポンス全体、プロンプト、画像バイナリは利用イベントへ保存しない。

## 利用イベント

成功時に`generation_provider_usage`を`usage_events`へ記録する。メタデータにはプロバイダー名、
審査プロバイダー／状態、トークン数、費用センチ単位を含められる。これは請求書発行サービス
そのものではなく、後段の費用集計・請求へ渡す内部の正規化境界である。
