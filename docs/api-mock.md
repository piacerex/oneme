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
- `GET /api/face_analysis_jobs`
- `GET /api/face_analysis_jobs/:id`
- `GET /api/ai_generation_jobs`
- `GET /api/ai_generation_jobs/:id`
- `GET /api/recommendation_feedback`
- `GET /api/export_jobs`
- `GET /api/export_jobs/:id`
- `GET /api/vrm_export_jobs`
- `GET /api/vrm_export_jobs/:id`
- `GET /api/apps`
- `GET /api/apps/:id`
- `GET /api/teams`
- `GET /api/teams/:id`
- `GET /api/team_members`
- `GET /api/team_members/:id`
- `GET /api/billing_plans`
- `GET /api/billing_plans/:id`
- `GET /api/rate_limit_policies`
- `GET /api/rate_limit_policies/:id`
- `GET /api/webhook_endpoints`
- `GET /api/webhook_endpoints/:id`
- `GET /api/webhook_deliveries/:id`
- `GET /api/usage_events`
- `GET /api/audit_logs`
- `GET /api/monitoring_alerts`
- `GET /api/incidents`
- `GET /api/legal_records`
- `GET /api/ops/summary`
- `GET /api/asset_reviews`
- `GET /api/asset_reviews/:id`
- `GET /api/asset_validations`
- `GET /api/asset_validations/:id`
- `GET /api/incidents/:id`
- `GET /api/legal_records/:id`
- `GET /api/webhook_deliveries`
- `PATCH /api/monitoring_alerts/:id`
- `PATCH /api/asset_reviews/:id`
- `PATCH /api/incidents/:id`
- `PATCH /api/legal_records/:id`
- `PATCH /api/team_members/:id`
- `PATCH /api/teams/:id`
- `PATCH /api/webhook_endpoints/:id`
- `PATCH /api/webhook_deliveries/:id`
- `DELETE /api/face_analysis_jobs/:id`
- `POST /api/avatars/from_face_analysis`
- `POST /api/avatars/from_ai_candidate`
- `POST /api/ai_generation_jobs`
- `POST /api/face_analysis_jobs`
- `POST /api/recommendation_feedback`
- `POST /api/apps`
- `POST /api/apps/:id/api_keys`
- `POST /api/teams`
- `POST /api/team_members`
- `POST /api/billing_plans`
- `POST /api/rate_limit_policies`
- `POST /api/export_jobs`
- `POST /api/vrm_export_jobs`
- `POST /api/asset_reviews`
- `POST /api/asset_validations`
- `POST /api/incidents`
- `POST /api/legal_records`
- `POST /api/webhook_endpoints`

The server stores avatars in memory and resets on restart. It is not a
production backend, but it gives SDK, widget, and API contract work a real HTTP
target before the hosted service exists.

Face analysis jobs are stored in memory and never retain the original photo.
`POST /api/face_analysis_jobs` requires consent and returns part, color,
pseudo-3D morph, and temporary face-texture recommendations. Use
`POST /api/avatars/from_face_analysis` to create an editable avatar from the
recommendation, and `DELETE /api/face_analysis_jobs/:id` to clear the temporary
texture state.
AI generation jobs are deterministic local MVP records. `POST
/api/ai_generation_jobs` creates safe part and texture candidates from the
current avatar config and safe hints only. `POST /api/avatars/from_ai_candidate`
turns an approved candidate into an editable avatar, and
`POST /api/recommendation_feedback` records whether the user applied, rejected,
or saved a candidate after edits.
Export jobs are stored in memory after `POST /api/export_jobs` and
`POST /api/vrm_export_jobs`. They can be listed or fetched by id so SDK and
operations flows can inspect async job state before a hosted queue exists.
`POST /api/export_jobs` with `simulateFailure` creates a local failed GLB job,
and `PATCH /api/export_jobs/:id` with `{"action":"retry"}` marks it succeeded
for incident recovery testing.
Widget apps are stored in memory through `POST /api/apps`. App API keys can be
added with `POST /api/apps/:id/api_keys` and revoked with
`DELETE /api/apps/:id/api_keys/:key`, which lets widget embed flows test app
configuration, credential lifecycle, and leaked-key recovery before production
auth exists.
Teams and members are stored in memory through `/api/teams` and
`/api/team_members`. Member creation and role changes append audit log records
for local role and access-control workflow testing.
Billing plans are stored in memory through `/api/billing_plans`. Updating a
team's `planId` with `PATCH /api/teams/:id` records a `billing.plan_changed`
audit event.
Rate limit policies are stored in memory through `/api/rate_limit_policies`.
The runtime limiter still uses the mock server flags, while policy records let
plan and dashboard flows inspect intended limits by plan and scope.

The mock applies a fixed-window API-key rate limit. It reads
`X-Oneme-Api-Key`, then `api_key`, and finally falls back to `anonymous`.
Responses include:

- `x-ratelimit-limit`
- `x-ratelimit-remaining`
- `x-ratelimit-reset`

Webhook endpoints are stored in memory. When matching events occur, the mock
creates queued delivery records that can be inspected with
`GET /api/webhook_deliveries`.
Webhook endpoints can be fetched or paused with `/api/webhook_endpoints/:id`.
Webhook deliveries can be fetched or retried with
`PATCH /api/webhook_deliveries/:id` and `{"action":"retry"}`.
Audit logs are stored in memory and exposed at `GET /api/audit_logs`.
Monitoring alerts are stored in memory and exposed at
`GET /api/monitoring_alerts`. API errors, including unsupported model formats
and rate limits, create open `api_error_rate` alerts that can be resolved with
`PATCH /api/monitoring_alerts/:id`.
Asset reviews are stored in memory and can be submitted or approved through
`/api/asset_reviews`.
Asset validations are stored in memory through `/api/asset_validations`.
Failed validations create open `asset_validation_failure` monitoring alerts.
Incidents are stored in memory and can be created, listed, fetched, and resolved
through `/api/incidents`. Incident creation and updates append audit log records
so recovery workflows can be inspected locally.
Status page updates are stored in memory through `/api/status_page_updates` and
can be linked to incident recovery flows before resolution.
Legal records are stored in memory and can be created, listed, fetched, and
updated through `/api/legal_records`. This covers terms, privacy, asset license,
face-photo consent, and retention-policy records for local operations testing.
Operations dashboard summaries are exposed at `GET /api/ops/summary`. The
response aggregates usage events, open alerts, open incidents, pending asset
reviews, webhook deliveries, and active legal records for the demo team/app.
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
event, audit log, face analysis, AI generation, asset review, incident recovery,
status page update, legal record, monitoring alert, operations summary, rate
limit, and webhook delivery endpoints.
