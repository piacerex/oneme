#!/usr/bin/env python3
"""Smoke test the dependency-free oneme API mock server."""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def request_json(base_url: str, path: str, method: str = "GET", payload: dict | None = None) -> dict:
    data = None
    headers = {"accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def wait_for_health(base_url: str) -> None:
    deadline = time.time() + 5
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            if request_json(base_url, "/health").get("ok") is True:
                return
        except (ConnectionError, urllib.error.URLError, TimeoutError) as error:
            last_error = error
            time.sleep(0.1)
    raise RuntimeError(f"API mock did not become healthy: {last_error}")


def assert_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def run_smoke(base_url: str) -> None:
    parts = request_json(base_url, "/api/parts")
    if not parts.get("parts"):
        raise AssertionError("/api/parts returned no parts")

    created = request_json(
        base_url,
        "/api/avatars",
        method="POST",
        payload={
            "avatarConfig": {
                "avatarId": "smoke-avatar",
                "parts": {"hair": "hair.long_01"},
                "colors": {"hair": "#445566"},
            }
        },
    )
    assert_equal(created["avatarId"], "smoke-avatar", "created avatar id")
    assert_equal(created["parts"]["hair"], "hair.long_01", "created avatar hair")

    patched = request_json(
        base_url,
        "/api/avatars/smoke-avatar",
        method="PATCH",
        payload={"colors": {"skin": "#abcdef"}},
    )
    assert_equal(patched["colors"]["skin"], "#abcdef", "patched avatar skin")

    config = request_json(base_url, "/api/avatars/smoke-avatar/config")
    assert_equal(config["avatarId"], "smoke-avatar", "config avatar id")

    glb = request_json(base_url, "/api/avatars/smoke-avatar/model?format=glb")
    assert_equal(glb["format"], "glb", "glb model format")

    vrm = request_json(base_url, "/api/avatars/smoke-avatar/model?format=vrm")
    assert_equal(vrm["format"], "vrm", "vrm model format")

    export_job = request_json(base_url, "/api/export_jobs", method="POST", payload={"avatarConfig": config})
    assert_equal(export_job["status"], "succeeded", "glb export status")

    vrm_job = request_json(base_url, "/api/vrm_export_jobs", method="POST", payload={"avatarConfig": config})
    assert_equal(vrm_job["status"], "succeeded", "vrm export status")
    if "vrm" not in vrm_job:
        raise AssertionError("vrm export job did not include VRM metadata")


def main() -> int:
    port = free_port()
    base_url = f"http://127.0.0.1:{port}"
    process = subprocess.Popen(
        [sys.executable, "apps/api/mock_server.py", "--port", str(port)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        wait_for_health(base_url)
        run_smoke(base_url)
    finally:
        process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate(timeout=5)

    if process.returncode not in {0, -15}:
        raise RuntimeError(f"API mock exited unexpectedly with {process.returncode}")

    print("ok: API mock smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
