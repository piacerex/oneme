#!/usr/bin/env python3
"""Smoke test widget API integration expectations."""

from __future__ import annotations

import importlib.util
import json
import socket
import subprocess
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WIDGET_FILE = ROOT / "apps/web/src/widget.js"
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


def request_json(base_url: str, path: str, method: str = "GET", payload: dict | None = None) -> dict:
    data = None
    headers = {"accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def assert_widget_surface() -> None:
    source = WIDGET_FILE.read_text(encoding="utf-8")
    expected = [
        'params.get("api")',
        "loadApiOptions",
        "loadResumeState",
        "createRemoteAvatar",
        "fetchJson",
        '"/api/parts"',
        '"/api/avatars"',
        '"oneme.widget.resumed"',
        "`oneme.widget.${resumeAvatarId}`",
    ]
    missing = [token for token in expected if token not in source]
    if missing:
        raise AssertionError(f"Widget missing API surface tokens: {', '.join(missing)}")


def main() -> int:
    assert_widget_surface()

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
        parts = request_json(base_url, "/api/parts")
        avatar = request_json(
            base_url,
            "/api/avatars",
            method="POST",
            payload={"avatarConfig": {"avatarId": "widget-smoke-avatar"}},
        )
    finally:
        process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate(timeout=5)

    if not parts.get("parts"):
        raise AssertionError("API mock did not return parts for widget")
    if avatar["avatarId"] != "widget-smoke-avatar":
        raise AssertionError("API mock did not save widget avatar")

    print("ok: Widget API smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
