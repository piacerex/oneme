#!/usr/bin/env python3
"""Create an explicit report for external runtime and export validation."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_binary(configured: str | None, candidates: tuple[str, ...]) -> str | None:
    names = (configured,) if configured else candidates
    for name in names:
        if not name:
            continue
        path = Path(name)
        if path.is_file():
            return str(path.resolve())
        found = shutil.which(name)
        if found:
            return str(Path(found).resolve())
    return None


def runtime_report(name: str, configured: str | None, candidates: tuple[str, ...]) -> dict:
    path = find_binary(configured, candidates)
    if path:
        return {
            "status": "available",
            "path": path,
            "verification": "not_run",
            "reason": "runtime was detected; run the project-specific import test",
        }

    return {
        "status": "missing",
        "path": None,
        "verification": "not_run",
        "reason": f"{name} executable was not found",
    }


def validate_artifact(repo_root: Path, kind: str, raw_path: str) -> dict:
    path = Path(raw_path).expanduser().resolve()
    result = {"path": str(path), "kind": kind, "status": "missing"}
    if not path.is_file():
        result["error"] = "artifact file does not exist"
        return result

    if kind in {"glb", "vrm"}:
        command = [
            sys.executable,
            str(repo_root / "apps/oneme/priv/exporter/validate_glb.py"),
            "--input",
            str(path),
        ]
        if kind == "vrm":
            command.append("--require-vrm")
    else:
        command = [
            sys.executable,
            str(repo_root / "apps/oneme/priv/exporter/validate_fbx.py"),
            "--input",
            str(path),
        ]

    try:
        completed = subprocess.run(
            command,
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        result["status"] = "invalid"
        result["error"] = str(error)
        return result

    result["status"] = "validated" if completed.returncode == 0 else "invalid"
    output = (completed.stdout or completed.stderr).strip()
    if output:
        result["validatorOutput"] = output
    return result


def build_report(args: argparse.Namespace, repo_root: Path) -> dict:
    artifacts = []
    for kind, raw_path in (("glb", args.glb), ("vrm", args.vrm), ("fbx", args.fbx)):
        if raw_path:
            artifacts.append(validate_artifact(repo_root, kind, raw_path))

    runtimes = {
        "blender": runtime_report(
            "Blender",
            args.blender or os.environ.get("ONEME_BLENDER_BIN"),
            ("blender", "blender.exe"),
        ),
        "unity": runtime_report(
            "Unity",
            args.unity or os.environ.get("ONEME_UNITY_BIN"),
            ("Unity", "Unity.exe", "unity-editor"),
        ),
    }

    unity_project = None
    if args.unity_project:
        project_path = Path(args.unity_project).expanduser().resolve()
        unity_project = {
            "path": str(project_path),
            "status": "available" if project_path.is_dir() else "missing",
        }

    next_actions = []
    for name, runtime in runtimes.items():
        if runtime["status"] == "missing":
            next_actions.append(f"install {name} and rerun this report")
        else:
            next_actions.append(f"run the {name} project import test against the artifacts")
    if unity_project and unity_project["status"] == "missing":
        next_actions.append("provide an existing Unity project with the Avatar Viewer sample")

    return {
        "artifacts": artifacts,
        "runtimes": runtimes,
        "unityProject": unity_project,
        "nextActions": next_actions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", help="path to a GLB artifact")
    parser.add_argument("--vrm", help="path to a VRM artifact")
    parser.add_argument("--fbx", help="path to an FBX artifact")
    parser.add_argument("--blender", help="Blender executable path")
    parser.add_argument("--unity", help="Unity executable path")
    parser.add_argument("--unity-project", help="Unity project to use for import testing")
    parser.add_argument(
        "--require-runtime",
        action="append",
        choices=("blender", "unity"),
        default=[],
        help="fail when the named runtime is not detected",
    )
    parser.add_argument("--json", action="store_true", help="emit compact JSON")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    report = build_report(args, repo_root)
    if args.json:
        print(json.dumps(report, separators=(",", ":")))
    else:
        print(json.dumps(report, indent=2))

    invalid_artifacts = any(item["status"] != "validated" for item in report["artifacts"])
    missing_required_runtime = any(
        report["runtimes"][name]["status"] != "available"
        for name in args.require_runtime
    )
    return 2 if invalid_artifacts or missing_required_runtime else 0


if __name__ == "__main__":
    raise SystemExit(main())
