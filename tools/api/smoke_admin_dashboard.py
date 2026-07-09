#!/usr/bin/env python3
"""Smoke test the Phase 8 admin dashboard and ops summary contract."""

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
    headers = {"accept": "application/json", "x-oneme-api-key": "admin-dashboard-smoke"}
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


def seed_operational_state(base_url: str) -> None:
    request_json(
        base_url,
        "/api/teams",
        method="POST",
        payload={"id": "team-admin-smoke", "name": "Admin Smoke Team", "planId": "plan-admin-smoke"},
    )
    request_json(
        base_url,
        "/api/team_members",
        method="POST",
        payload={"id": "member-admin-smoke", "teamId": "team-admin-smoke", "userId": "user-admin", "role": "owner"},
    )
    request_json(
        base_url,
        "/api/apps",
        method="POST",
        payload={
            "id": "app-admin-smoke",
            "name": "Admin Smoke App",
            "allowedOrigins": ["https://admin.example.com"],
        },
    )
    request_json(
        base_url,
        "/api/webhook_endpoints",
        method="POST",
        payload={
            "id": "webhook-admin-smoke",
            "appId": "app-admin-smoke",
            "events": ["avatar.created", "model.exported"],
            "url": "https://admin.example.com/oneme/webhooks",
        },
    )
    request_json(
        base_url,
        "/api/asset_reviews",
        method="POST",
        payload={
            "id": "asset-review-admin-smoke",
            "assetId": "hair-admin-smoke",
            "status": "submitted",
            "licenseStatus": "needs_review",
        },
    )
    request_json(
        base_url,
        "/api/incidents",
        method="POST",
        payload={
            "id": "incident-admin-smoke",
            "severity": "major",
            "status": "investigating",
            "summary": "Admin dashboard smoke incident",
            "recoveryActions": ["pause_webhook_endpoint", "publish_status_update"],
        },
    )
    request_json(
        base_url,
        "/api/export_jobs",
        method="POST",
        payload={"avatarConfig": {"avatarId": "admin-smoke-avatar"}, "simulateFailure": True},
    )
    request_json(
        base_url,
        "/api/avatars",
        method="POST",
        payload={"avatarConfig": {"avatarId": "admin-smoke-avatar"}},
    )

    deliveries = request_json(base_url, "/api/webhook_deliveries").get("webhookDeliveries", [])
    if not deliveries:
        raise AssertionError("seeding did not create webhook deliveries")

    request_json(
        base_url,
        f"/api/webhook_deliveries/{deliveries[0]['id']}",
        method="PATCH",
        payload={"status": "failed", "responseStatus": 503, "nextAttemptAt": "2026-07-09T00:01:00.000Z"},
    )


def run_smoke(base_url: str) -> None:
    seed_operational_state(base_url)
    ops_summary = request_json(base_url, "/api/ops/summary")
    dashboard = request_json(base_url, "/api/admin/dashboard")

    assert_equal(dashboard["summary"], ops_summary, "dashboard embedded ops summary")
    assert_equal(ops_summary["openIncidentCount"], 1, "ops summary open incident count")
    assert_equal(ops_summary["pendingAssetReviewCount"], 1, "ops summary pending asset review count")
    if ops_summary["openAlertCount"] < 1:
        raise AssertionError("ops summary did not count the open export alert")
    if ops_summary["webhookDeliveryCount"] < 1:
        raise AssertionError("ops summary did not count webhook deliveries")

    if "team-admin-smoke" not in {team["id"] for team in dashboard["teams"]}:
        raise AssertionError("admin dashboard did not include seeded team")
    if "member-admin-smoke" not in {member["id"] for member in dashboard["members"]}:
        raise AssertionError("admin dashboard did not include seeded member")
    if "app-admin-smoke" not in {app["id"] for app in dashboard["apps"]}:
        raise AssertionError("admin dashboard did not include seeded app")
    if "asset-review-admin-smoke" not in {review["id"] for review in dashboard["pendingAssetReviews"]}:
        raise AssertionError("admin dashboard did not include pending asset review")
    if "incident-admin-smoke" not in {incident["id"] for incident in dashboard["openIncidents"]}:
        raise AssertionError("admin dashboard did not include open incident")
    if not any(alert["metric"] == "export_job_failed" for alert in dashboard["openAlerts"]):
        raise AssertionError("admin dashboard did not include export failure alert")
    if not any(delivery["status"] == "failed" for delivery in dashboard["failedWebhookDeliveries"]):
        raise AssertionError("admin dashboard did not include failed webhook delivery")
    if not dashboard["recentAuditLogs"]:
        raise AssertionError("admin dashboard did not include recent audit logs")


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

    print("ok: Admin dashboard smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
