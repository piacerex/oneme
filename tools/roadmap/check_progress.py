#!/usr/bin/env python3
"""Check that roadmap phase evidence files exist."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

PHASES = [
    {
        "phase": "phase_0",
        "status": "mvp_done",
        "evidence": [
            "docs/avatar-direction.md",
            "docs/asset-conventions.md",
            "docs/mvp-parts.md",
            "schemas/avatar-config.schema.json",
        ],
    },
    {
        "phase": "phase_1",
        "status": "mvp_done",
        "evidence": [
            "apps/web/index.html",
            "apps/web/src/app.js",
            "apps/web/src/three-preview.js",
            "docs/three-preview.md",
        ],
        "checks": ["widget_api_smoke"],
    },
    {
        "phase": "phase_2",
        "status": "mvp_done",
        "evidence": [
            "apps/web/src/app.js",
            "schemas/avatar-config.schema.json",
            "schemas/face-analysis-job.schema.json",
        ],
        "checks": ["api_mock_smoke", "widget_api_smoke", "schema_example_validation"],
    },
    {
        "phase": "phase_3",
        "status": "mvp_done",
        "evidence": [
            "docs/ai-generation-mvp.md",
            "schemas/ai-generation-job.schema.json",
            "schemas/recommendation-feedback.schema.json",
        ],
        "checks": ["api_mock_smoke", "schema_example_validation"],
    },
    {
        "phase": "phase_4",
        "status": "mvp_done",
        "evidence": [
            "docs/export-api.md",
            "docs/export-pipeline.md",
            "tools/gltf/validate_glb.py",
            "tools/blender/compose_avatar.py",
        ],
        "checks": ["api_mock_smoke", "schema_example_validation"],
    },
    {
        "phase": "phase_5",
        "status": "mvp_done",
        "evidence": [
            "docs/widget-contract.md",
            "apps/web/widget.html",
            "apps/web/embed-example.html",
            "schemas/widget-app.schema.json",
        ],
        "checks": ["widget_api_smoke"],
    },
    {
        "phase": "phase_6",
        "status": "mvp_done",
        "evidence": [
            "docs/web-sdk.md",
            "packages/sdk-web/package.json",
            "docs/unity-sdk.md",
            "packages/sdk-unity/package.json",
        ],
        "checks": ["web_sdk_smoke", "unity_sdk_smoke"],
    },
    {
        "phase": "phase_7",
        "status": "contract_done",
        "evidence": [
            "docs/vrm.md",
            "docs/vrm-validation.md",
            "schemas/vrm-export-job.schema.json",
            "tools/gltf/create_sample_vrm.py",
            "tools/gltf/validate_vrm.py",
        ],
        "checks": ["api_mock_smoke", "vrm_sample_validation"],
    },
    {
        "phase": "phase_8",
        "status": "contract_done",
        "evidence": [
            "docs/commercial-operations.md",
            "schemas/team.schema.json",
            "schemas/usage-event.schema.json",
            "schemas/billing-plan.schema.json",
            "schemas/webhook-endpoint.schema.json",
            "schemas/audit-log.schema.json",
            "schemas/asset-review.schema.json",
            "schemas/asset-validation.schema.json",
            "schemas/monitoring-alert.schema.json",
            "schemas/incident.schema.json",
            "schemas/status-page-update.schema.json",
            "schemas/legal-record.schema.json",
            "schemas/ops-summary.schema.json",
        ],
        "checks": ["api_mock_smoke", "schema_example_validation"],
    },
]


def check_phase(phase: dict) -> dict:
    missing = [path for path in phase["evidence"] if not (ROOT / path).exists()]
    checks = phase.get("checks", [])
    return {
        "phase": phase["phase"],
        "status": phase["status"],
        "evidenceCount": len(phase["evidence"]),
        "checks": checks,
        "checkCount": len(checks),
        "missing": missing,
        "ok": not missing,
    }


def main() -> int:
    results = [check_phase(phase) for phase in PHASES]
    ok = all(result["ok"] for result in results)
    print(json.dumps({"ok": ok, "phases": results}, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
