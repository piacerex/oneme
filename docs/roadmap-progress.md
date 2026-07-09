# Roadmap Progress

This document maps the current repository artifacts to the roadmap phases.

## Status Legend

- `mvp_done`: implemented as a local/browser MVP or documented contract
- `contract_done`: schema and operational contract exist, production code still follows
- `production_pending`: requires hosted backend, production assets, or external service integration

`tools/roadmap/check_progress.py` reports both evidence files and phase-linked
local checks. File evidence proves the roadmap artifact exists; check names map
that phase to the smoke or validation command exercised by `tools/check_all.py`.

## Phase Status

| Phase | Status | Evidence |
| --- | --- | --- |
| Phase 0: planning | `mvp_done` | `docs/avatar-direction.md`, `docs/asset-conventions.md`, `docs/mvp-parts.md`, `schemas/avatar-config.schema.json` |
| Phase 1: MVP builder | `mvp_done` | `apps/web/index.html`, `apps/web/src/app.js`, `apps/web/src/three-preview.js`, `docs/three-preview.md`; checked by `web_builder_smoke` |
| Phase 2: face photo proposal | `mvp_done` | `apps/web/src/app.js`, `schemas/avatar-config.schema.json`, `schemas/face-analysis-job.schema.json`; checked by `face_photo_surface_smoke` |
| Phase 3: AI generation MVP | `mvp_done` | `docs/ai-generation-mvp.md`, `schemas/ai-generation-job.schema.json`, `schemas/recommendation-feedback.schema.json` |
| Phase 4: GLB export | `mvp_done` | `docs/export-api.md`, `docs/export-pipeline.md`, `tools/gltf/validate_glb.py`, `tools/blender/compose_avatar.py` |
| Phase 5: widget | `mvp_done` | `docs/widget-contract.md`, `apps/web/widget.html`, `apps/web/embed-example.html`, `apps/web/src/widget.js`, `schemas/widget-app.schema.json` |
| Phase 6: SDKs | `mvp_done` | `docs/web-sdk.md`, `packages/sdk-web/package.json`, `docs/unity-sdk.md`, `packages/sdk-unity/package.json` |
| Phase 7: VRM | `contract_done` | `docs/vrm.md`, `docs/vrm-validation.md`, `schemas/vrm-export-job.schema.json`, `tools/gltf/create_sample_vrm.py`, `tools/gltf/validate_vrm.py`; checked by `vrm_contract_smoke` |
| Phase 8: commercial operations | `contract_done` | `docs/commercial-operations.md`, team, admin dashboard, usage, billing usage, billing, webhook, audit, asset review, asset validation, monitoring, incident, status page update, legal, and ops summary schemas |

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
python3 tools/check_all.py
```

The full check runner validates schema JSON, Python tooling, and roadmap
evidence coverage. It also runs API mock, Web builder, face photo surface, Web
SDK, Widget API, VRM sample validation, and VRM contract checks that are
referenced by the phase progress output.
`tools/roadmap/check_progress.py` can still be run directly when only phase
evidence and check mapping should be inspected. These checks do not prove
production readiness.
