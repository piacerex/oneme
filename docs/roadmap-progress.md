# Roadmap Progress

This document maps the current repository artifacts to the roadmap phases.

## Status Legend

- `mvp_done`: implemented as a local/browser MVP or documented contract
- `contract_done`: schema and operational contract exist, production code still follows
- `production_pending`: requires hosted backend, production assets, or external service integration

## Phase Status

| Phase | Status | Evidence |
| --- | --- | --- |
| Phase 0: planning | `mvp_done` | `docs/avatar-direction.md`, `docs/asset-conventions.md`, `docs/mvp-parts.md`, `schemas/avatar-config.schema.json` |
| Phase 1: MVP builder | `mvp_done` | `apps/web/index.html`, `apps/web/src/app.js`, `apps/web/src/three-preview.js`, `docs/three-preview.md` |
| Phase 2: face photo proposal | `mvp_done` | `apps/web/src/app.js`, `schemas/avatar-config.schema.json` |
| Phase 3: AI generation MVP | `mvp_done` | `docs/ai-generation-mvp.md`, `schemas/ai-generation-job.schema.json`, `schemas/recommendation-feedback.schema.json` |
| Phase 4: GLB export | `mvp_done` | `docs/export-api.md`, `docs/export-pipeline.md`, `tools/gltf/validate_glb.py`, `tools/blender/compose_avatar.py` |
| Phase 5: widget | `mvp_done` | `docs/widget-contract.md`, `apps/web/widget.html`, `apps/web/embed-example.html`, `schemas/widget-app.schema.json` |
| Phase 6: SDKs | `mvp_done` | `docs/web-sdk.md`, `packages/sdk-web/package.json`, `docs/unity-sdk.md`, `packages/sdk-unity/package.json` |
| Phase 7: VRM | `contract_done` | `docs/vrm.md`, `docs/vrm-validation.md`, `schemas/vrm-export-job.schema.json`, `tools/gltf/validate_vrm.py` |
| Phase 8: commercial operations | `contract_done` | `docs/commercial-operations.md`, team, usage, billing, webhook, audit, asset review, monitoring, incident, and legal schemas |

## Remaining Production Work

- Replace placeholder browser/local storage flows with hosted APIs and database persistence.
- Replace procedural previews and placeholder GLB containers with production rigged assets.
- Export true merged `.glb` files from a server-side pipeline.
- Export true VRM 1.0 humanoid payloads with rigged meshes, skinning, expressions, and spring bones.
- Implement server-side auth, teams, usage metering, billing, webhooks, audit logs, monitoring, and admin UI.
- Validate production assets and SDKs in real Web, Three.js, Unity, GLB, and VRM environments.

## Local Verification

Run:

```bash
python3 tools/roadmap/check_progress.py
```

The script verifies the expected roadmap evidence files exist and reports phase
coverage. It does not prove production readiness.
