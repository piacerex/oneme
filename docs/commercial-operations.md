# Commercial Operations

Phase 8 prepares oneme for multiple production apps.

## Accounts

Commercial usage is scoped by team.

- A team owns apps, API keys, billing plans, usage records, webhooks, and assets.
- A member belongs to a team with a role.
- App-level API keys inherit the team's limits.

## Roles

- `owner`: manage billing, members, apps, API keys, and assets
- `admin`: manage apps, API keys, webhooks, and assets
- `developer`: read app settings and use SDK/API credentials
- `viewer`: read dashboards and audit logs

## Usage Metrics

Minimum billable metrics:

- `avatar_created`
- `model_exported`
- `model_downloaded`
- `api_request`
- `storage_byte_hour`

Usage is recorded per team and app. API key id is included when available.
The local API mock exposes `GET /api/usage_events` so SDK and widget flows can
inspect generated usage events before production telemetry exists.

## Rate Limits

The first production limiter is API-key scoped.

- Free: 60 requests per minute
- Pro: 600 requests per minute
- Enterprise: custom

Limit decisions must return the remaining quota and reset time so SDKs can back
off without guessing.
The local API mock implements this with `x-ratelimit-limit`,
`x-ratelimit-remaining`, and `x-ratelimit-reset` headers.

## Billing Plans

Plans define soft and hard limits for:

- app count
- member count
- monthly API requests
- monthly model exports
- storage bytes
- webhook deliveries

## Operations Dashboard

The admin dashboard should expose:

- teams and members
- apps and API keys
- usage by metric
- export job health
- webhook delivery failures
- asset review queue
- audit log search

## Webhooks

Apps can subscribe to production events.

Minimum events:

- `avatar.created`
- `model.exported`
- `export.failed`
- `asset.reviewed`

Deliveries use signed JSON payloads and exponential retry. Failed deliveries stay
queryable from the operations dashboard.

## Audit Logs

Audit logs are append-only records for administrative and security-sensitive
actions.

Minimum actions:

- `team.member.invited`
- `team.member.role_changed`
- `app.created`
- `api_key.created`
- `api_key.revoked`
- `asset.reviewed`
- `billing.plan_changed`

## Asset Review

Production assets must pass review before they can be used by commercial apps.

Review states:

- `draft`
- `submitted`
- `approved`
- `rejected`
- `archived`

Review records keep the reviewer, decision, license status, and notes.

## Monitoring

Production monitoring tracks:

- export job latency and failures
- API error rates by app and endpoint
- CDN delivery errors
- webhook delivery failures
- asset validation failures

Alerts should include team id, app id, severity, metric, and a runbook link.

## Incident Recovery

Incidents record detection, mitigation, customer impact, and follow-up tasks.

Minimum recovery actions:

- retry failed export jobs
- pause a broken webhook endpoint
- revoke a leaked API key
- roll back a rejected asset
- publish a status page update

## Legal and License Records

Commercial operation keeps structured records for:

- terms of service version
- privacy policy version
- asset license source and usage rights
- consent requirements for face-photo analysis
- retention policy for generated artifacts
