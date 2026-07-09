#!/usr/bin/env python3
"""Run the local verification checks for the oneme MVP repository."""

from __future__ import annotations

import json
import py_compile
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PYTHON_FILES = [
    "tools/blender/compose_avatar.py",
    "tools/gltf/validate_glb.py",
    "tools/gltf/validate_vrm.py",
    "tools/roadmap/check_progress.py",
    "tools/check_all.py",
]


def check_json_files() -> None:
    for path in sorted((ROOT / "schemas").glob("*.json")):
        with path.open("r", encoding="utf-8") as file:
            json.load(file)


def check_python_files() -> None:
    for relative_path in PYTHON_FILES:
        py_compile.compile(str(ROOT / relative_path), doraise=True)


def check_roadmap_progress() -> None:
    subprocess.run(
        [sys.executable, "tools/roadmap/check_progress.py"],
        cwd=ROOT,
        check=True,
    )


def main() -> int:
    checks = [
        ("schemas", check_json_files),
        ("python", check_python_files),
        ("roadmap", check_roadmap_progress),
    ]

    for name, check in checks:
        check()
        print(f"ok: {name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
