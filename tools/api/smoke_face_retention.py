#!/usr/bin/env python3
"""Smoke test Phase 2 face-photo retention and deletion contracts."""

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
    headers = {"accept": "application/json", "x-oneme-api-key": "face-retention-smoke"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def request_status(base_url: str, path: str, method: str = "GET", payload: dict | None = None) -> int:
    data = None
    headers = {"accept": "application/json", "x-oneme-api-key": "face-retention-smoke"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


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
    no_consent = request_status(
        base_url,
        "/api/face_analysis_jobs",
        method="POST",
        payload={"id": "face-no-consent", "consentAccepted": False},
    )
    assert_equal(no_consent, 400, "face analysis without consent status")

    job = request_json(
        base_url,
        "/api/face_analysis_jobs",
        method="POST",
        payload={
            "id": "face-retention-job",
            "consentAccepted": True,
            "retentionSeconds": 300,
            "mapFaceTexture": True,
        },
    )
    assert_equal(job["photoRetention"]["storesOriginalPhoto"], False, "stores original photo")
    assert_equal(job["photoRetention"]["retentionSeconds"], 300, "retention seconds")
    assert_equal(job["recommendation"]["faceTexture"]["temporary"], True, "temporary face texture")

    avatar = request_json(
        base_url,
        "/api/avatars/from_face_analysis",
        method="POST",
        payload={"avatarId": "face-retention-avatar", "faceAnalysisJobId": job["id"]},
    )
    assert_equal(avatar["source"]["kind"], "face_recommendation", "face avatar source kind")

    deleted = request_json(base_url, f"/api/face_analysis_jobs/{job['id']}", method="DELETE")
    assert_equal(deleted["status"], "deleted", "deleted face job status")
    assert_equal(deleted["recommendation"]["faceTexture"]["enabled"], False, "deleted face texture enabled")
    deleted_reuse = request_status(
        base_url,
        "/api/avatars/from_face_analysis",
        method="POST",
        payload={"avatarId": "face-retention-deleted-avatar", "faceAnalysisJobId": job["id"]},
    )
    assert_equal(deleted_reuse, 404, "deleted face job reuse status")

    expired = request_json(
        base_url,
        "/api/face_analysis_jobs",
        method="POST",
        payload={
            "id": "face-expired-job",
            "consentAccepted": True,
            "expiresAt": "2026-07-08T23:59:59.000Z",
        },
    )
    assert_equal(expired["expiresAt"], "2026-07-08T23:59:59.000Z", "expired face job expiresAt")
    expired_reuse = request_status(
        base_url,
        "/api/avatars/from_face_analysis",
        method="POST",
        payload={"avatarId": "face-expired-avatar", "faceAnalysisJobId": expired["id"]},
    )
    assert_equal(expired_reuse, 404, "expired face job reuse status")


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

    print("ok: Face retention smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
