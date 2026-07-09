# Export API

Phase 4 exposes a local API-shaped contract for GLB export jobs.
Phase 7 extends the same model URL contract to VRM exports.

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

Optional query:

```http
GET /api/avatars/:id/model?format=vrm
```

Supported formats:

- `glb`
- `vrm`

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

VRM response:

```json
{
  "avatarId": "local-demo",
  "format": "vrm",
  "modelUrl": "blob:oneme-vrm-local",
  "exportJobId": "vrm-local-1",
  "cacheHit": false
}
```

## VRM Export Job

```http
POST /api/vrm_export_jobs
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
  "id": "vrm-local-1",
  "status": "queued",
  "vrm": {
    "meta": {},
    "humanoid": {},
    "expressions": [],
    "springBones": []
  },
  "createdAt": "2026-07-09T00:00:00.000Z"
}
```

## MVP Notes

- The browser implementation stores job records in `localStorage`.
- `modelUrl` is a temporary object URL.
- The same visual config reuses the cached GLB payload.
- VRM MVP exports are GLB containers with VRM-shaped metadata, not final rigged VRM 1.0 assets.
- Failed jobs retain an error message and can be retried by creating another job.
