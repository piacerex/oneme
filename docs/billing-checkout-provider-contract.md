# 課金チェックアウトプロバイダー契約

`POST /api/billing/checkout`はowner権限のAPIキーで呼び出す。onemeはカード番号、
CVC、カードトークンなどの決済情報を受け取らず、外部プロバイダーがホストする
チェックアウトページへ遷移するためのURLだけを返す。

## APIリクエスト

```json
{
  "planSlug": "pro",
  "successUrl": "https://app.example/billing/success",
  "cancelUrl": "https://app.example/billing/cancel",
  "idempotencyKey": "team-42-checkout-20260713-1"
}
```

`successUrl`と`cancelUrl`はHTTPS URLを必須とする。`idempotencyKey`はクライアントが
生成し、同じチェックアウト操作の再送では同じ値を使う。

## プロバイダー接続

次の環境変数でHTTP JSONの接続先を設定する。

- `ONEME_BILLING_CHECKOUT_URL`（本番はHTTPS必須）
- `ONEME_BILLING_CHECKOUT_API_KEY`（任意のBearerトークン）
- `ONEME_BILLING_ALLOW_INSECURE_HTTP=true`（localhost開発時だけ）
- `ONEME_BILLING_CHECKOUT_TIMEOUT_MS`（既定30秒）
- `ONEME_BILLING_CHECKOUT_CONNECT_TIMEOUT_MS`（既定5秒）
- `ONEME_BILLING_CHECKOUT_MAX_ATTEMPTS`（既定2、1〜5）
- `ONEME_BILLING_CHECKOUT_RETRY_DELAY_MS`（既定250ミリ秒）

プロバイダーへは次の正規化済みリクエストを送る。任意の入力フィールドは送信せず、
カード情報が渡されても許可リストで除外する。

```json
{
  "kind": "subscription_checkout",
  "teamId": 42,
  "plan": {
    "slug": "pro",
    "currency": "jpy",
    "monthlyPriceCents": 1980
  },
  "successUrl": "https://app.example/billing/success",
  "cancelUrl": "https://app.example/billing/cancel"
}
```

`x-oneme-api-version: v1`、`x-oneme-request-id`、`idempotency-key`を付与する。408、
425、429、5xx、接続障害だけを、同じ冪等キーで限定的に再試行する。プロバイダーは
このキーを使って重複セッションを作らないこと。

## レスポンス

```json
{
  "provider": "billing-provider",
  "sessionId": "cs_123",
  "checkoutUrl": "https://checkout.example/session/cs_123",
  "status": "pending"
}
```

`checkoutUrl`はHTTPS URLだけを受け入れる。Webhookで契約・請求書状態を確定するため、
チェックアウト成功レスポンスだけで`team_subscriptions`を有効化しない。

この契約は決済プロバイダーのSDK接続前のアダプターであり、実決済、請求書発行、
支払い失敗通知、カード情報処理は各プロバイダーの本番設定と法務要件を満たした後に
有効化する。
