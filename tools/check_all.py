#!/usr/bin/env python3
"""Run the local verification checks for the oneme MVP repository."""

from __future__ import annotations

import json
import py_compile
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PYTHON_FILES = [
    "apps/api/mock_server.py",
    "tools/assets/smoke_asset_inventory.py",
    "tools/api/smoke_ai_generation.py",
    "tools/api/smoke_admin_dashboard.py",
    "tools/api/smoke_face_retention.py",
    "tools/api/smoke_mock_api.py",
    "tools/blender/compose_avatar.py",
    "tools/gltf/create_sample_glb.py",
    "tools/gltf/create_sample_vrm.py",
    "tools/gltf/smoke_glb_contract.py",
    "tools/gltf/smoke_vrm_contract.py",
    "tools/gltf/validate_glb.py",
    "tools/gltf/validate_vrm.py",
    "tools/roadmap/check_progress.py",
    "tools/schemas/validate_examples.py",
    "tools/sdk/smoke_web_sdk.py",
    "tools/sdk/smoke_unity_sdk.py",
    "tools/web/smoke_builder_surface.py",
    "tools/web/smoke_face_photo_surface.py",
    "tools/widget/smoke_widget_api.py",
    "tools/check_all.py",
]


def check_json_files() -> None:
    for path in sorted((ROOT / "schemas").glob("*.json")):
        with path.open("r", encoding="utf-8") as file:
            json.load(file)


def check_schema_examples() -> None:
    missing_examples = []
    orphan_examples = []
    schema_names = {
        path.name.removesuffix(".schema.json")
        for path in (ROOT / "schemas").glob("*.schema.json")
    }
    example_names = {
        path.name.removesuffix(".example.json")
        for path in (ROOT / "schemas").glob("*.example.json")
    }

    for name in sorted(schema_names):
        if name not in example_names:
            missing_examples.append(f"schemas/{name}.example.json")

    for name in sorted(example_names):
        if name not in schema_names:
            orphan_examples.append(f"schemas/{name}.example.json")

    if missing_examples or orphan_examples:
        details = []
        if missing_examples:
            details.append(f"missing examples: {', '.join(missing_examples)}")
        if orphan_examples:
            details.append(f"orphan examples: {', '.join(orphan_examples)}")
        raise RuntimeError("; ".join(details))


def check_python_files() -> None:
    for relative_path in PYTHON_FILES:
        py_compile.compile(str(ROOT / relative_path), doraise=True)


def check_roadmap_progress() -> None:
    subprocess.run(
        [sys.executable, "tools/roadmap/check_progress.py"],
        cwd=ROOT,
        check=True,
    )


def check_schema_example_validation() -> None:
    subprocess.run(
        [sys.executable, "tools/schemas/validate_examples.py"],
        cwd=ROOT,
        check=True,
    )


def check_asset_inventory() -> None:
    subprocess.run(
        [sys.executable, "tools/assets/smoke_asset_inventory.py"],
        cwd=ROOT,
        check=True,
    )


def check_api_mock() -> None:
    subprocess.run(
        [sys.executable, "tools/api/smoke_mock_api.py"],
        cwd=ROOT,
        check=True,
    )


def check_admin_dashboard() -> None:
    subprocess.run(
        [sys.executable, "tools/api/smoke_admin_dashboard.py"],
        cwd=ROOT,
        check=True,
    )


def check_ai_generation() -> None:
    subprocess.run(
        [sys.executable, "tools/api/smoke_ai_generation.py"],
        cwd=ROOT,
        check=True,
    )


def check_face_retention() -> None:
    subprocess.run(
        [sys.executable, "tools/api/smoke_face_retention.py"],
        cwd=ROOT,
        check=True,
    )


def check_web_sdk() -> None:
    subprocess.run(
        [sys.executable, "tools/sdk/smoke_web_sdk.py"],
        cwd=ROOT,
        check=True,
    )


def check_unity_sdk() -> None:
    subprocess.run(
        [sys.executable, "tools/sdk/smoke_unity_sdk.py"],
        cwd=ROOT,
        check=True,
    )


def check_widget_api() -> None:
    subprocess.run(
        [sys.executable, "tools/widget/smoke_widget_api.py"],
        cwd=ROOT,
        check=True,
    )


def check_glb_contract() -> None:
    subprocess.run(
        [sys.executable, "smoke_glb_contract.py"],
        cwd=ROOT / "tools/gltf",
        check=True,
    )


def check_web_builder() -> None:
    subprocess.run(
        [sys.executable, "tools/web/smoke_builder_surface.py"],
        cwd=ROOT,
        check=True,
    )


def check_face_photo_surface() -> None:
    subprocess.run(
        [sys.executable, "tools/web/smoke_face_photo_surface.py"],
        cwd=ROOT,
        check=True,
    )


def check_vrm_sample() -> None:
    with tempfile.TemporaryDirectory() as directory:
        sample = Path(directory) / "local-demo.vrm"
        subprocess.run(
            [sys.executable, "tools/gltf/create_sample_vrm.py", "--out", str(sample)],
            cwd=ROOT,
            check=True,
        )
        subprocess.run(
            [sys.executable, "tools/gltf/validate_vrm.py", str(sample)],
            cwd=ROOT,
            check=True,
        )


def check_vrm_contract() -> None:
    subprocess.run(
        [sys.executable, "smoke_vrm_contract.py"],
        cwd=ROOT / "tools/gltf",
        check=True,
    )


def main() -> int:
    checks = [
        ("schemas", check_json_files),
        ("schema examples", check_schema_examples),
        ("schema example validation", check_schema_example_validation),
        ("python", check_python_files),
        ("asset inventory", check_asset_inventory),
        ("api mock", check_api_mock),
        ("admin dashboard", check_admin_dashboard),
        ("ai generation", check_ai_generation),
        ("face retention", check_face_retention),
        ("web sdk", check_web_sdk),
        ("unity sdk", check_unity_sdk),
        ("web builder", check_web_builder),
        ("face photo surface", check_face_photo_surface),
        ("widget api", check_widget_api),
        ("glb contract", check_glb_contract),
        ("vrm sample", check_vrm_sample),
        ("vrm contract", check_vrm_contract),
        ("roadmap", check_roadmap_progress),
    ]

    for name, check in checks:
        check()
        print(f"ok: {name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
