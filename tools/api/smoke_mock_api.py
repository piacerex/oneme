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


def request_status(base_url: str, path: str, api_key: str = "rate-smoke") -> int:
    request = urllib.request.Request(
        f"{base_url}{path}",
        headers={"accept": "application/json", "x-oneme-api-key": api_key},
        method="GET",
    )
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
    parts = request_json(base_url, "/api/parts")
    if not parts.get("parts"):
        raise AssertionError("/api/parts returned no parts")

    webhook = request_json(
        base_url,
        "/api/webhook_endpoints",
        method="POST",
        payload={
            "id": "webhook-smoke",
            "url": "https://example.com/oneme/webhooks",
            "events": ["asset.reviewed", "avatar.created", "model.exported"],
        },
    )
    assert_equal(webhook["status"], "active", "webhook endpoint status")

    asset_review = request_json(
        base_url,
        "/api/asset_reviews",
        method="POST",
        payload={
            "id": "asset-review-smoke",
            "assetId": "hair-short-placeholder",
            "status": "submitted",
            "licenseStatus": "needs_review",
        },
    )
    assert_equal(asset_review["status"], "submitted", "created asset review status")

    approved_review = request_json(
        base_url,
        "/api/asset_reviews/asset-review-smoke",
        method="PATCH",
        payload={
            "status": "approved",
            "licenseStatus": "verified",
            "decision": "approve",
            "reviewerId": "user-demo",
        },
    )
    assert_equal(approved_review["status"], "approved", "approved asset review status")

    incident = request_json(
        base_url,
        "/api/incidents",
        method="POST",
        payload={
            "id": "incident-smoke",
            "severity": "major",
            "status": "mitigating",
            "summary": "Smoke test export incident",
            "recoveryActions": ["retry_export_jobs", "publish_status_update"],
            "customerImpact": "Model exports are delayed in the smoke test.",
        },
    )
    assert_equal(incident["status"], "mitigating", "created incident status")

    incidents = request_json(base_url, "/api/incidents")
    incident_ids = {item["id"] for item in incidents.get("incidents", [])}
    if "incident-smoke" not in incident_ids:
        raise AssertionError("incidents did not include incident-smoke")

    resolved_incident = request_json(
        base_url,
        "/api/incidents/incident-smoke",
        method="PATCH",
        payload={"status": "resolved"},
    )
    assert_equal(resolved_incident["status"], "resolved", "resolved incident status")
    if "resolvedAt" not in resolved_incident:
        raise AssertionError("resolved incident did not include resolvedAt")

    legal_record = request_json(
        base_url,
        "/api/legal_records",
        method="POST",
        payload={
            "id": "legal-smoke",
            "kind": "asset_license",
            "version": "2026-07-09",
            "status": "draft",
            "sourceUrl": "https://example.com/licenses/oneme-placeholder-assets",
            "usageRights": ["commercial", "redistribution", "modification"],
        },
    )
    assert_equal(legal_record["status"], "draft", "created legal record status")

    legal_records = request_json(base_url, "/api/legal_records")
    legal_ids = {item["id"] for item in legal_records.get("legalRecords", [])}
    if "legal-smoke" not in legal_ids:
        raise AssertionError("legal records did not include legal-smoke")

    active_legal_record = request_json(
        base_url,
        "/api/legal_records/legal-smoke",
        method="PATCH",
        payload={"status": "active"},
    )
    assert_equal(active_legal_record["status"], "active", "active legal record status")

    assert_equal(
        request_status(base_url, "/api/face_analysis_jobs", api_key="face-smoke"),
        200,
        "face analysis list status",
    )
    face_job = request_json(
        base_url,
        "/api/face_analysis_jobs",
        method="POST",
        payload={
            "id": "face-job-smoke",
            "consentAccepted": True,
            "skinColor": "#c99686",
            "hairColor": "#2d2420",
            "mapFaceTexture": True,
        },
    )
    assert_equal(face_job["status"], "succeeded", "face analysis job status")
    assert_equal(face_job["photoRetention"]["storesOriginalPhoto"], False, "face photo original retention")
    if not face_job["recommendation"]["faceTexture"]["temporary"]:
        raise AssertionError("face analysis texture was not marked temporary")

    face_avatar = request_json(
        base_url,
        "/api/avatars/from_face_analysis",
        method="POST",
        payload={"avatarId": "face-avatar-smoke", "faceAnalysisJobId": "face-job-smoke"},
    )
    assert_equal(face_avatar["source"]["kind"], "face_recommendation", "face avatar source kind")
    assert_equal(face_avatar["faceTexture"]["temporary"], True, "face avatar temporary texture")

    deleted_face_job = request_json(base_url, "/api/face_analysis_jobs/face-job-smoke", method="DELETE")
    assert_equal(deleted_face_job["status"], "deleted", "deleted face analysis job status")
    assert_equal(deleted_face_job["recommendation"]["faceTexture"]["enabled"], False, "deleted face texture enabled")

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

    animation_compat = request_json(base_url, "/api/avatars/smoke-avatar/animation_compat?format=vrm")
    assert_equal(animation_compat["format"], "vrm", "animation compat format")
    assert_equal(animation_compat["status"], "contract_ready", "animation compat status")
    if animation_compat["missingHumanoidBones"]:
        raise AssertionError("animation compatibility reported missing humanoid bones")
    for expression in {"neutral", "happy", "blink", "surprised"}:
        if expression not in animation_compat["expressions"]:
            raise AssertionError(f"animation compatibility did not include {expression}")

    export_job = request_json(base_url, "/api/export_jobs", method="POST", payload={"avatarConfig": config})
    assert_equal(export_job["status"], "succeeded", "glb export status")

    vrm_job = request_json(base_url, "/api/vrm_export_jobs", method="POST", payload={"avatarConfig": config})
    assert_equal(vrm_job["status"], "succeeded", "vrm export status")
    if "vrm" not in vrm_job:
        raise AssertionError("vrm export job did not include VRM metadata")

    usage = request_json(base_url, "/api/usage_events")
    metrics = {event["metric"] for event in usage.get("usageEvents", [])}
    for metric in {"avatar_created", "model_downloaded", "model_exported", "api_request"}:
        if metric not in metrics:
            raise AssertionError(f"usage events did not include {metric}")

    deliveries = request_json(base_url, "/api/webhook_deliveries")
    events = {delivery["event"] for delivery in deliveries.get("webhookDeliveries", [])}
    for event in {"avatar.created", "model.exported", "asset.reviewed"}:
        if event not in events:
            raise AssertionError(f"webhook deliveries did not include {event}")

    audit = request_json(base_url, "/api/audit_logs")
    actions = {log["action"] for log in audit.get("auditLogs", [])}
    for action in {
        "asset.reviewed",
        "avatar.created",
        "avatar.updated",
        "incident.created",
        "incident.updated",
        "face_analysis.deleted",
        "legal_record.created",
        "legal_record.updated",
        "model.exported",
        "webhook_endpoint.created",
    }:
        if action not in actions:
            raise AssertionError(f"audit logs did not include {action}")

    assert_equal(
        request_status(base_url, "/api/avatars/smoke-avatar/model?format=fbx", api_key="alert-smoke"),
        400,
        "unsupported model format",
    )
    alerts = request_json(base_url, "/api/monitoring_alerts")
    open_alerts = [alert for alert in alerts.get("monitoringAlerts", []) if alert["status"] == "open"]
    if not open_alerts:
        raise AssertionError("monitoring alerts did not include an open alert")
    assert_equal(open_alerts[0]["metric"], "api_error_rate", "monitoring alert metric")

    resolved_alert = request_json(
        base_url,
        f"/api/monitoring_alerts/{open_alerts[0]['id']}",
        method="PATCH",
        payload={"status": "resolved"},
    )
    assert_equal(resolved_alert["status"], "resolved", "resolved monitoring alert status")
    if "resolvedAt" not in resolved_alert:
        raise AssertionError("resolved monitoring alert did not include resolvedAt")

    ops_summary = request_json(base_url, "/api/ops/summary")
    if ops_summary["usageEventCount"] <= 0:
        raise AssertionError("ops summary did not include usage events")
    assert_equal(ops_summary["openIncidentCount"], 0, "ops summary open incident count")
    assert_equal(ops_summary["activeLegalRecordCount"], 1, "ops summary active legal record count")
    if ops_summary["webhookDeliveryCount"] <= 0:
        raise AssertionError("ops summary did not include webhook deliveries")


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

    run_rate_limit_smoke()
    print("ok: API mock smoke")
    return 0


def run_rate_limit_smoke() -> None:
    port = free_port()
    base_url = f"http://127.0.0.1:{port}"
    process = subprocess.Popen(
        [
            sys.executable,
            "apps/api/mock_server.py",
            "--port",
            str(port),
            "--rate-limit",
            "2",
            "--rate-limit-window",
            "60",
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        wait_for_health(base_url)
        assert_equal(request_status(base_url, "/api/parts"), 200, "first limited request")
        assert_equal(request_status(base_url, "/api/parts"), 200, "second limited request")
        assert_equal(request_status(base_url, "/api/parts"), 429, "rate limited request")
    finally:
        process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
