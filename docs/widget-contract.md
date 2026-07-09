# Widget Contract

Phase 5 provides a static iframe MVP that can later be backed by server APIs.

## Embed URL

```text
apps/web/widget.html?app_id=demo-app&api_key=demo-key
```

Optional parameters:

- `theme`: `light`, `mint`, or `mono`
- `resume`: avatar id to resume from local storage
- `api`: optional API base URL for loading parts and saving avatars through the API mock

## App Configuration

The widget resolves the app configuration from `apps/web/src/widget-apps.js` in the MVP.
Production should resolve the same contract from:

- `POST /api/apps`
- `POST /api/apps/:id/api_keys`
- `GET /widget?app_id=...`

## Allowed Parts

Each app can limit choices by category:

```json
{
  "allowedParts": {
    "hair": ["hair.short_01", "hair.medium_01"],
    "accessory": ["accessory.none"]
  }
}
```

Missing categories allow all MVP options.

When `api` is present, the widget calls `/api/parts` and uses matching returned
parts for supported categories.

## postMessage Events

The widget sends messages to `window.parent`.

### Ready

```json
{
  "type": "oneme.widget.ready",
  "appId": "demo-app"
}
```

### Avatar Saved

```json
{
  "type": "oneme.avatar.saved",
  "appId": "demo-app",
  "avatarId": "local-123",
  "config": {}
}
```

### Error

```json
{
  "type": "oneme.widget.error",
  "appId": "demo-app",
  "error": "Invalid app credentials"
}
```

## Origin Policy

The static MVP cannot enforce server CORS. It simulates embed policy by checking
`document.referrer` against the configured `allowedOrigins` list where available.
Production must enforce this server-side.

## API Mock Save

With `api=http://127.0.0.1:8765`, the widget saves through:

```http
POST /api/avatars
```

Without `api`, it keeps the static MVP behavior and writes to `localStorage`.
