#!/usr/bin/env python3
"""Smoke test Web SDK API-surface expectations against the API mock."""

from __future__ import annotations

import importlib.util
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SDK_FILE = ROOT / "packages/sdk-web/src/oneme-web-sdk.js"
API_SMOKE = ROOT / "tools/api/smoke_mock_api.py"


def load_api_smoke_module():
    spec = importlib.util.spec_from_file_location("smoke_mock_api", API_SMOKE)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load API smoke module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def request_json(base_url: str, path: str) -> dict:
    with urllib.request.urlopen(f"{base_url}{path}", timeout=5) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def assert_sdk_surface() -> None:
    source = SDK_FILE.read_text(encoding="utf-8")
    expected = [
        "async fetchAvatar(",
        "async fetchModel(",
        "async fetchParts(",
        "apiBaseUrl",
        "#requestJson(",
    ]
    missing = [token for token in expected if token not in source]
    if missing:
        raise AssertionError(f"Web SDK missing API surface tokens: {', '.join(missing)}")


def main() -> int:
    assert_sdk_surface()

    api_smoke = load_api_smoke_module()
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
        api_smoke.wait_for_health(base_url)
        avatar = request_json(base_url, "/api/avatars/demo-avatar")
        model = request_json(base_url, "/api/avatars/demo-avatar/model?format=vrm")
        parts = request_json(base_url, "/api/parts")
    finally:
        process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate(timeout=5)

    if avatar["avatarId"] != "demo-avatar":
        raise AssertionError("API mock did not return the expected demo avatar")
    if model["format"] != "vrm":
        raise AssertionError("API mock did not return the requested VRM model response")
    if not parts.get("parts"):
        raise AssertionError("API mock did not return parts for SDK fetchParts")

    print("ok: Web SDK API smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
