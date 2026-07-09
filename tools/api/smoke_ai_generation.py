#!/usr/bin/env python3
"""Smoke test the Phase 3 AI generation MVP contract."""

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
    headers = {"accept": "application/json", "x-oneme-api-key": "ai-generation-smoke"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def request_status(base_url: str, path: str, method: str = "GET", payload: dict | None = None) -> int:
    data = None
    headers = {"accept": "application/json", "x-oneme-api-key": "ai-generation-smoke"}
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
    avatar_config = {
        "avatarId": "ai-generation-smoke-avatar",
        "style": "semi_real_lightweight",
        "parts": {
            "baseBody": "base_body.default",
            "face": "face.soft_01",
            "hair": "hair.short_01",
            "top": "top.basic_01",
            "bottom": "bottom.basic_01",
            "shoes": "shoes.basic_01",
            "accessory": "accessory.none",
        },
        "colors": {
            "skin": "#c98f6f",
            "hair": "#2f2118",
        },
    }
    safe_hints = {
        "skinColor": "#c98f6f",
        "hairColor": "#2f2118",
        "facePreset": "face.soft_01",
        "hairPreset": "hair.short_01",
    }

    job = request_json(
        base_url,
        "/api/ai_generation_jobs",
        method="POST",
        payload={
            "id": "ai-generation-smoke-job",
            "avatarConfig": avatar_config,
            "safeHints": safe_hints,
            "includeRejectedCandidate": True,
        },
    )

    assert_equal(job["status"], "succeeded", "ai generation job status")
    assert_equal(job["input"]["safeHints"], safe_hints, "ai generation safe hints")

    candidates = job["candidates"]
    styles = {candidate["stylePreset"] for candidate in candidates}
    for style in {"clean", "expressive", "event"}:
        if style not in styles:
            raise AssertionError(f"ai generation candidates did not include {style}")

    approved = [candidate for candidate in candidates if candidate["safety"]["status"] == "approved"]
    rejected = [candidate for candidate in candidates if candidate["safety"]["status"] == "rejected"]
    if len(approved) < 3:
        raise AssertionError("ai generation did not include three approved candidates")
    if not rejected:
        raise AssertionError("ai generation did not include rejected safety candidate")

    if any(not candidate.get("cacheKey") for candidate in candidates):
        raise AssertionError("ai generation candidates did not include cache keys")
    approved_cache_keys = {candidate["cacheKey"] for candidate in approved}
    if len(approved_cache_keys) != len(approved):
        raise AssertionError("approved ai generation candidates did not include unique cache keys")

    for candidate in approved:
        if not candidate["textureCandidate"]["palette"]:
            raise AssertionError(f"{candidate['id']} did not include a palette")
        if candidate["configPatch"].get("source", {}).get("kind") != "ai_generation":
            raise AssertionError(f"{candidate['id']} did not route through ai_generation source")

    avatar = request_json(
        base_url,
        "/api/avatars/from_ai_candidate",
        method="POST",
        payload={
            "avatarId": "ai-generation-applied-avatar",
            "jobId": job["id"],
            "candidateId": approved[0]["id"],
        },
    )
    assert_equal(avatar["source"]["kind"], "ai_generation", "avatar source kind")
    assert_equal(avatar["source"]["candidateId"], approved[0]["id"], "avatar source candidate id")

    rejected_status = request_status(
        base_url,
        "/api/avatars/from_ai_candidate",
        method="POST",
        payload={
            "avatarId": "ai-generation-rejected-avatar",
            "jobId": job["id"],
            "candidateId": rejected[0]["id"],
        },
    )
    assert_equal(rejected_status, 404, "rejected candidate avatar create status")

    feedback = request_json(
        base_url,
        "/api/recommendation_feedback",
        method="POST",
        payload={
            "id": "ai-generation-feedback",
            "jobId": job["id"],
            "candidateId": approved[0]["id"],
            "action": "saved_after_edit",
        },
    )
    assert_equal(feedback["action"], "saved_after_edit", "recommendation feedback action")

    feedback_records = request_json(base_url, "/api/recommendation_feedback").get("recommendationFeedback", [])
    if "ai-generation-feedback" not in {record["id"] for record in feedback_records}:
        raise AssertionError("recommendation feedback list did not include saved feedback")


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

    print("ok: AI generation smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
