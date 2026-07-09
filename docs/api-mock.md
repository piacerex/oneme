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
- `GET /api/avatars/:id/animation_compat?format=vrm`
- `GET /api/usage_events`
- `GET /api/audit_logs`
- `GET /api/monitoring_alerts`
- `GET /api/incidents`
- `GET /api/legal_records`
- `GET /api/asset_reviews`
- `GET /api/asset_reviews/:id`
- `GET /api/incidents/:id`
- `GET /api/legal_records/:id`
- `GET /api/webhook_deliveries`
- `PATCH /api/monitoring_alerts/:id`
- `PATCH /api/asset_reviews/:id`
- `PATCH /api/incidents/:id`
- `PATCH /api/legal_records/:id`
- `POST /api/export_jobs`
- `POST /api/vrm_export_jobs`
- `POST /api/asset_reviews`
- `POST /api/incidents`
- `POST /api/legal_records`
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
Monitoring alerts are stored in memory and exposed at
`GET /api/monitoring_alerts`. API errors, including unsupported model formats
and rate limits, create open `api_error_rate` alerts that can be resolved with
`PATCH /api/monitoring_alerts/:id`.
Asset reviews are stored in memory and can be submitted or approved through
`/api/asset_reviews`.
Incidents are stored in memory and can be created, listed, fetched, and resolved
through `/api/incidents`. Incident creation and updates append audit log records
so recovery workflows can be inspected locally.
Legal records are stored in memory and can be created, listed, fetched, and
updated through `/api/legal_records`. This covers terms, privacy, asset license,
face-photo consent, and retention-policy records for local operations testing.
VRM animation compatibility can be checked through
`GET /api/avatars/:id/animation_compat?format=vrm`. The MVP response reports
the Phase 7 humanoid bone target set, expression presets, and the current
contract-level readiness state.

Smoke test:

```bash
python3 tools/api/smoke_mock_api.py
```

The smoke test starts the mock on a temporary local port and verifies avatar,
parts, model URL, GLB export, VRM export, VRM animation compatibility, usage
event, audit log, asset review, incident recovery, legal record, monitoring
alert, rate limit, and webhook delivery endpoints.
