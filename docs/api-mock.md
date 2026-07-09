# API Mock

`apps/api/mock_server.py` is a dependency-free local API mock for roadmap API
contracts.

Run:

```bash
python3 apps/api/mock_server.py --port 8765
```

Optional rate limit flags:

```bash
python3 apps/api/mock_server.py --rate-limit 600 --rate-limit-window 60
```

Implemented endpoints:

- `GET /health`
- `GET /api/parts`
- `POST /api/avatars`
- `GET /api/avatars/:id`
- `PATCH /api/avatars/:id`
- `GET /api/avatars/:id/config`
- `GET /api/avatars/:id/model?format=glb`
- `GET /api/avatars/:id/model?format=vrm`
- `GET /api/usage_events`
- `GET /api/audit_logs`
- `GET /api/asset_reviews`
- `GET /api/asset_reviews/:id`
- `GET /api/webhook_deliveries`
- `PATCH /api/asset_reviews/:id`
- `POST /api/export_jobs`
- `POST /api/vrm_export_jobs`
- `POST /api/asset_reviews`
- `POST /api/webhook_endpoints`

The server stores avatars in memory and resets on restart. It is not a
production backend, but it gives SDK, widget, and API contract work a real HTTP
target before the hosted service exists.

The mock applies a fixed-window API-key rate limit. It reads
`X-Oneme-Api-Key`, then `api_key`, and finally falls back to `anonymous`.
Responses include:

- `x-ratelimit-limit`
- `x-ratelimit-remaining`
- `x-ratelimit-reset`

Webhook endpoints are stored in memory. When matching events occur, the mock
creates queued delivery records that can be inspected with
`GET /api/webhook_deliveries`.
Audit logs are stored in memory and exposed at `GET /api/audit_logs`.
Asset reviews are stored in memory and can be submitted or approved through
`/api/asset_reviews`.

Smoke test:

```bash
python3 tools/api/smoke_mock_api.py
```

The smoke test starts the mock on a temporary local port and verifies avatar,
parts, model URL, GLB export, VRM export, usage event, audit log, asset review,
rate limit, and webhook delivery endpoints.
