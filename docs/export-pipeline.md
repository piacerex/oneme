# Export Pipeline

Phase 3 starts with a local MVP exporter and keeps the contract compatible with a later server-side Blender pipeline.

## MVP Export Contract

The browser exporter creates a valid `.glb` container with:

- a glTF 2.0 JSON chunk
- an empty scene
- `asset.extras.oneme.config` containing the avatar configuration
- `asset.extras.oneme.resolvedParts` containing part resolution output

This does not yet merge real meshes. It proves the export job lifecycle, cache key, model URL handoff, and GLB validation path.

## Later Server Pipeline

1. Resolve avatar configuration into concrete part assets.
2. Queue an export job.
3. Run Blender Python to merge compatible meshes.
4. Run glTF validation.
5. Run gltf-transform optimization.
6. Store the generated `.glb`.
7. Return job status and model URL.

## Job States

- `queued`
- `running`
- `succeeded`
- `failed`

## Cache Key

The MVP cache key is a stable JSON string of:

- `style`
- `parts`
- `colors`

The same visual avatar should reuse the same generated GLB.

## Error Policy

- Keep failed jobs in the local job list.
- Store a short error message.
- Allow users to retry by pressing export again.
