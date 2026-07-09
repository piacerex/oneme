# Web SDK

Phase 6 starts with a small browser SDK that reads oneme avatar data from the
current MVP storage contracts. Later it can swap local storage for hosted APIs.

## Public API

```js
import {
  OnemeClient,
  createThreeAvatar,
  mountThreeAvatar
} from "./oneme-web-sdk.js";
```

### `new OnemeClient(options)`

Options:

- `storage`: storage-compatible object, defaults to `window.localStorage`
- `apiBaseUrl`: optional hosted or mock API base URL
- `fetch`: optional fetch-compatible function
- `avatarPrefix`: saved avatar prefix, defaults to `oneme.avatars`
- `exportJobsKey`: export job list key, defaults to `oneme.exportJobs`
- `exportCacheKey`: GLB cache key, defaults to `oneme.exportCache`

### `client.getAvatar(avatarId)`

Returns a saved avatar config by id.

### `client.getLatestAvatar()`

Returns the latest saved avatar config.

### `client.getModel(avatarId)`

Returns the latest GLB model response for an avatar id if an export exists.

### `client.fetchAvatar(avatarId)`

Fetches an avatar config from `/api/avatars/:id`.

### `client.fetchModel(avatarId, options)`

Fetches a model response from `/api/avatars/:id/model`.

Options:

- `format`: `glb` or `vrm`, defaults to `glb`

### `client.fetchPublicAvatar(avatarId)`

Fetches public sharing URLs from `/api/avatars/:id/public`.

### `client.fetchParts()`

Fetches available avatar parts from `/api/parts`.

### `client.createFaceAnalysisJob(payload)`

Creates a face analysis job through `/api/face_analysis_jobs`.

### `client.createAvatarFromFaceAnalysis(payload)`

Creates an editable avatar from a face analysis job through
`/api/avatars/from_face_analysis`.

### `client.createAiGenerationJob(payload)`

Creates deterministic local AI-style candidates through `/api/ai_generation_jobs`.

### `client.fetchAiGenerationJob(jobId)`

Fetches an AI generation job and its candidate cache keys through
`/api/ai_generation_jobs/:id`.

### `client.createAvatarFromAiCandidate(payload)`

Creates an editable avatar from an approved AI candidate through
`/api/avatars/from_ai_candidate`.

### `client.createRecommendationFeedback(payload)`

Records candidate feedback through `/api/recommendation_feedback`.

### `client.listRecommendationFeedback()`

Lists recommendation feedback records from `/api/recommendation_feedback`.

### `client.createExportJob(payload, options)`

Creates a GLB export job through `/api/export_jobs`, or a VRM job through
`/api/vrm_export_jobs` when `options.format` is `vrm`.

### `client.fetchExportJob(jobId, options)`

Fetches a GLB or VRM export job by id.
The Web SDK smoke verifies VRM export metadata and humanoid data against the
local API mock.

### `client.createWidgetApp(payload)`

Creates a widget app configuration through `/api/apps`.

### `client.createAppApiKey(appId, payload)`

Creates an API key for a widget app through `/api/apps/:id/api_keys`.

### `client.revokeAppApiKey(appId, apiKey)`

Revokes an API key for a widget app through `/api/apps/:id/api_keys/:key`.
The Web SDK smoke verifies this path against the local API mock.

### `client.fetchAdminDashboard()`

Fetches the Phase 8 admin dashboard payload from `/api/admin/dashboard`.

### `client.fetchBillingUsage(teamId)`

Fetches plan usage and remaining quota from `/api/billing_usage/:team_id`.

### `client.createStatusPageUpdate(payload)`

Publishes an incident status page update through `/api/status_page_updates`.

### `client.listExportJobs()`

Returns known export jobs.

### `createThreeAvatar(config, THREE)`

Creates a procedural Three.js avatar group from config.

### `mountThreeAvatar(container, config, options)`

Mounts a self-contained Three.js preview in a container.

## MVP Limits

- It reads local MVP data from `localStorage`.
- It can fetch from the dependency-free API mock or a compatible hosted API.
- It renders procedural geometry, not production `.glb` assets.
- Real package publishing is represented by `packages/sdk-web/package.json`.
