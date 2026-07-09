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


def request_json(base_url: str, path: str, method: str = "GET", payload: dict | None = None) -> dict:
    data = None
    headers = {"accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["content-type"] = "application/json"

    request = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=5) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def assert_sdk_surface() -> None:
    source = SDK_FILE.read_text(encoding="utf-8")
    expected = [
        "async fetchAvatar(",
        "async fetchModel(",
        "async fetchParts(",
        "async createFaceAnalysisJob(",
        "async createAiGenerationJob(",
        "async fetchAiGenerationJob(",
        "async listRecommendationFeedback(",
        "async createExportJob(",
        "async createWidgetApp(",
        "async createAppApiKey(",
        "async revokeAppApiKey(",
        "async fetchAdminDashboard(",
        "async fetchBillingUsage(",
        "async createStatusPageUpdate(",
        '"/api/admin/dashboard"',
        '"/api/recommendation_feedback"',
        "`/api/ai_generation_jobs/",
        '"/api/status_page_updates"',
        "`/api/billing_usage/",
        "apiBaseUrl",
        "#requestJson(",
        "method: options.method",
        "JSON.stringify(options.body)",
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
        animation = request_json(base_url, "/api/avatars/demo-avatar/animation_compat?format=vrm")
        ai_generation = request_json(
            base_url,
            "/api/ai_generation_jobs",
            method="POST",
            payload={
                "id": "sdk-ai-generation",
                "avatarConfig": avatar,
                "includeRejectedCandidate": True,
            },
        )
        fetched_ai_generation = request_json(base_url, "/api/ai_generation_jobs/sdk-ai-generation")
        feedback = request_json(
            base_url,
            "/api/recommendation_feedback",
            method="POST",
            payload={
                "id": "sdk-ai-feedback",
                "jobId": "sdk-ai-generation",
                "candidateId": "candidate-clean",
                "action": "applied",
            },
        )
        feedback_records = request_json(base_url, "/api/recommendation_feedback")
        vrm_export = request_json(base_url, "/api/vrm_export_jobs", method="POST", payload={"avatarConfig": avatar})
        fetched_vrm_export = request_json(base_url, f"/api/vrm_export_jobs/{vrm_export['id']}")
        request_json(base_url, "/api/teams", method="POST", payload={"id": "sdk-team", "planId": "plan-pro"})
        request_json(base_url, "/api/apps", method="POST", payload={"id": "sdk-app", "name": "SDK App"})
        request_json(base_url, "/api/apps/sdk-app/api_keys", method="POST", payload={"apiKey": "sdk-key"})
        revoked_key = request_json(base_url, "/api/apps/sdk-app/api_keys/sdk-key", method="DELETE")
        billing_usage = request_json(base_url, "/api/billing_usage/sdk-team")
        dashboard = request_json(base_url, "/api/admin/dashboard")
        status_update = request_json(
            base_url,
            "/api/status_page_updates",
            method="POST",
            payload={"id": "sdk-status-update", "incidentId": "sdk-incident", "status": "monitoring", "message": "SDK smoke"},
        )
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
    if animation["status"] != "contract_ready":
        raise AssertionError("API mock did not return animation compatibility for SDK clients")
    if fetched_ai_generation["id"] != ai_generation["id"]:
        raise AssertionError("API mock did not return AI generation job for SDK clients")
    if not all(candidate.get("cacheKey") for candidate in fetched_ai_generation["candidates"]):
        raise AssertionError("API mock did not return AI candidate cache keys for SDK clients")
    if feedback["action"] != "applied":
        raise AssertionError("API mock did not create recommendation feedback for SDK clients")
    if "sdk-ai-feedback" not in {record["id"] for record in feedback_records.get("recommendationFeedback", [])}:
        raise AssertionError("API mock did not list recommendation feedback for SDK clients")
    if fetched_vrm_export["vrm"]["meta"]["commercialUsage"] != "allowed":
        raise AssertionError("API mock did not return VRM export metadata for SDK clients")
    if len(fetched_vrm_export["vrm"]["humanoid"]) < 17:
        raise AssertionError("API mock did not return VRM humanoid data for SDK clients")
    if billing_usage["teamId"] != "sdk-team":
        raise AssertionError("API mock did not return billing usage for SDK clients")
    if revoked_key["revoked"] is not True or "sdk-key" in revoked_key["apiKeys"]:
        raise AssertionError("API mock did not revoke app API key for SDK clients")
    if "summary" not in dashboard:
        raise AssertionError("API mock did not return admin dashboard for SDK clients")
    if status_update["status"] != "monitoring":
        raise AssertionError("API mock did not create status page update for SDK clients")

    print("ok: Web SDK API smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
