# 監視通知契約

`ONEME_MONITORING_ALERT_URL`を設定すると、CDNプローブの結果を次のJSONで外部通知する。
通知先は本番ではHTTPS必須で、`ONEME_MONITORING_ALERT_SECRET`によるHMAC-SHA256署名を
`x-oneme-monitoring-signature`へ付ける。

```json
{
  "event": "oneme.monitoring",
  "report": {
    "status": "degraded",
    "historicalSlo": {
      "probeCount": 100,
      "probeAvailabilityPercent": 99.0
    }
  }
}
```

ヘッダーには次を付ける。

- `x-oneme-api-version: v1`
- `x-oneme-monitoring-event-id: monitoring-<sha256(body)>`
- `idempotency-key: monitoring-<sha256(body)>`
- `x-oneme-monitoring-signature: sha256=<hmac-sha256(body)>`

408、425、429、5xx、接続障害だけを同じイベントIDで限定再試行する。通知先はイベントIDを
冪等キーとして扱い、同じ通知を二重にアラート化しないこと。外部監視サービスのSLO集計、
通知抑制、severityごとのポリシー、オンコール連携は通知先側の本番設定で確定する。
