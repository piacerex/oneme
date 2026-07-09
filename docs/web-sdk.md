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
- `avatarPrefix`: saved avatar prefix, defaults to `oneme.avatars`
- `exportJobsKey`: export job list key, defaults to `oneme.exportJobs`
- `exportCacheKey`: GLB cache key, defaults to `oneme.exportCache`

### `client.getAvatar(avatarId)`

Returns a saved avatar config by id.

### `client.getLatestAvatar()`

Returns the latest saved avatar config.

### `client.getModel(avatarId)`

Returns the latest GLB model response for an avatar id if an export exists.

### `client.listExportJobs()`

Returns known export jobs.

### `createThreeAvatar(config, THREE)`

Creates a procedural Three.js avatar group from config.

### `mountThreeAvatar(container, config, options)`

Mounts a self-contained Three.js preview in a container.

## MVP Limits

- It reads local MVP data from `localStorage`.
- It does not fetch hosted avatars yet.
- It renders procedural geometry, not production `.glb` assets.
- Real package publishing is represented by `packages/sdk-web/package.json`.
