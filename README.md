# oneme

oneme is a local MVP for a Ready Player Me-style avatar creation service.

The repository currently focuses on proving the product path phase by phase:

- browser avatar builder with Canvas and Three.js previews
- face-photo based local recommendations and temporary face texture mapping
- deterministic AI-style avatar candidates
- local GLB and VRM-shaped export jobs
- iframe widget contract
- Web and Unity SDK skeletons
- commercial operation contracts for teams, usage, billing, webhooks, audit logs, asset review, monitoring, incidents, and legal records

See `ROADMAP.md` for the full phased plan and `docs/roadmap-progress.md` for
the current implementation evidence.

## Open the MVP

The browser MVP is static HTML.

Open:

```text
apps/web/index.html
```

Useful companion pages:

- `apps/web/widget.html`
- `apps/web/embed-example.html`
- `apps/web/sdk-example.html`

## Local Verification

Run the repository gate before committing:

```bash
python3 tools/check_all.py
```

This verifies:

- JSON syntax for every schema and example in `schemas/`
- Python syntax for local tools
- roadmap phase evidence with `tools/roadmap/check_progress.py`

## Key Documents

- `docs/avatar-direction.md`: avatar style and MVP structure
- `docs/three-preview.md`: Phase 1 Three.js preview
- `docs/ai-generation-mvp.md`: Phase 3 local AI generation contract
- `docs/export-api.md`: GLB/VRM model response contract
- `docs/export-pipeline.md`: GLB export pipeline
- `docs/widget-contract.md`: iframe widget integration
- `docs/web-sdk.md`: Web SDK contract
- `docs/unity-sdk.md`: Unity SDK contract
- `docs/vrm.md`: VRM export contract
- `docs/vrm-validation.md`: VRM validation and animation compatibility checks
- `docs/commercial-operations.md`: Phase 8 commercial operation contracts

## Current Limits

The MVP is intentionally local and contract-first. Production work still needs:

- hosted API and database persistence
- production 3D assets
- real merged GLB output
- true VRM 1.0 humanoid exports
- server-side auth, billing, rate limits, webhooks, monitoring, and admin UI
- browser, Unity, GLB, and VRM viewer validation with production artifacts
