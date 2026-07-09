# Export API

Phase 4 exposes a local API-shaped contract for GLB export jobs.

## Create Export Job

```http
POST /api/export_jobs
```

Request:

```json
{
  "avatarConfig": {}
}
```

Response:

```json
{
  "id": "export-local-1",
  "status": "queued",
  "cacheKey": "stable-visual-config-key",
  "createdAt": "2026-07-09T00:00:00.000Z"
}
```

## Get Export Job

```http
GET /api/export_jobs/:id
```

Response:

```json
{
  "id": "export-local-1",
  "status": "succeeded",
  "modelUrl": "blob:oneme-local",
  "cacheHit": false,
  "finishedAt": "2026-07-09T00:00:01.000Z"
}
```

## Get Avatar Model

```http
GET /api/avatars/:id/model
```

Response:

```json
{
  "avatarId": "local-demo",
  "format": "glb",
  "modelUrl": "blob:oneme-local",
  "exportJobId": "export-local-1",
  "cacheHit": false
}
```

## MVP Notes

- The browser implementation stores job records in `localStorage`.
- `modelUrl` is a temporary object URL.
- The same visual config reuses the cached GLB payload.
- Failed jobs retain an error message and can be retried by creating another job.
