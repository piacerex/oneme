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

## Rate Limits

The first production limiter is API-key scoped.

- Free: 60 requests per minute
- Pro: 600 requests per minute
- Enterprise: custom

Limit decisions must return the remaining quota and reset time so SDKs can back
off without guessing.

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
