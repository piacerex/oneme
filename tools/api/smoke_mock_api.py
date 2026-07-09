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


def request_status_json(base_url: str, path: str, method: str = "GET", payload: dict | None = None) -> int:
    data = None
    headers = {"accept": "application/json"}
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
    parts = request_json(base_url, "/api/parts")
    if not parts.get("parts"):
        raise AssertionError("/api/parts returned no parts")

    team = request_json(
        base_url,
        "/api/teams",
        method="POST",
        payload={"id": "team-smoke", "name": "Smoke Studio", "planId": "plan-pro"},
    )
    assert_equal(team["name"], "Smoke Studio", "created team name")

    member = request_json(
        base_url,
        "/api/team_members",
        method="POST",
        payload={"id": "member-smoke", "teamId": "team-smoke", "userId": "user-smoke", "role": "developer"},
    )
    assert_equal(member["role"], "developer", "created team member role")

    updated_member = request_json(
        base_url,
        "/api/team_members/member-smoke",
        method="PATCH",
        payload={"role": "admin"},
    )
    assert_equal(updated_member["role"], "admin", "updated team member role")
    fetched_team = request_json(base_url, "/api/teams/team-smoke")
    assert_equal(fetched_team["id"], "team-smoke", "fetched team id")

    billing_plan = request_json(
        base_url,
        "/api/billing_plans",
        method="POST",
        payload={
            "id": "plan-smoke",
            "name": "Smoke Pro",
            "currency": "USD",
            "monthlyPriceCents": 9900,
            "limits": {
                "apps": 5,
                "members": 10,
                "monthlyApiRequests": 100000,
                "monthlyModelExports": 5000,
                "storageBytes": 10737418240,
                "webhookDeliveries": 50000,
            },
        },
    )
    assert_equal(billing_plan["limits"]["apps"], 5, "billing plan app limit")
    fetched_plan = request_json(base_url, "/api/billing_plans/plan-smoke")
    assert_equal(fetched_plan["id"], "plan-smoke", "fetched billing plan id")
    patched_team = request_json(
        base_url,
        "/api/teams/team-smoke",
        method="PATCH",
        payload={"planId": "plan-smoke"},
    )
    assert_equal(patched_team["planId"], "plan-smoke", "patched team billing plan")
    billing_usage = request_json(base_url, "/api/billing_usage/team-smoke")
    assert_equal(billing_usage["planId"], "plan-smoke", "billing usage plan id")
    assert_equal(billing_usage["limits"]["apps"], 5, "billing usage app limit")
    if billing_usage["remaining"]["members"] > billing_usage["limits"]["members"]:
        raise AssertionError("billing usage remaining members exceeded limit")

    rate_policy = request_json(
        base_url,
        "/api/rate_limit_policies",
        method="POST",
        payload={
            "id": "rate-policy-smoke",
            "planId": "plan-smoke",
            "scope": "api_key",
            "windowSeconds": 60,
            "limit": 120,
            "burstLimit": 180,
        },
    )
    assert_equal(rate_policy["limit"], 120, "rate limit policy limit")
    fetched_rate_policy = request_json(base_url, "/api/rate_limit_policies/rate-policy-smoke")
    assert_equal(fetched_rate_policy["burstLimit"], 180, "fetched rate limit policy burst")
    rate_policies = request_json(base_url, "/api/rate_limit_policies")
    if "rate-policy-smoke" not in {policy["id"] for policy in rate_policies.get("rateLimitPolicies", [])}:
        raise AssertionError("rate limit policies did not include rate-policy-smoke")

    widget_app = request_json(
        base_url,
        "/api/apps",
        method="POST",
        payload={
            "id": "app-smoke",
            "name": "Smoke Widget App",
            "theme": "mint",
            "allowedOrigins": ["https://example.com"],
            "allowedParts": {"hair": ["hair.short_01", "hair.medium_01"], "accessory": ["accessory.none"]},
        },
    )
    assert_equal(widget_app["theme"], "mint", "widget app theme")

    api_key = request_json(
        base_url,
        "/api/apps/app-smoke/api_keys",
        method="POST",
        payload={"apiKey": "key-smoke"},
    )
    assert_equal(api_key["apiKey"], "key-smoke", "created app api key")

    fetched_app = request_json(base_url, "/api/apps/app-smoke")
    if "key-smoke" not in fetched_app["apiKeys"]:
        raise AssertionError("widget app did not include created API key")

    revoked_api_key = request_json(base_url, "/api/apps/app-smoke/api_keys/key-smoke", method="DELETE")
    assert_equal(revoked_api_key["revoked"], True, "revoked app api key")
    fetched_app_after_revoke = request_json(base_url, "/api/apps/app-smoke")
    if "key-smoke" in fetched_app_after_revoke["apiKeys"]:
        raise AssertionError("widget app still included revoked API key")

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
    fetched_webhook = request_json(base_url, "/api/webhook_endpoints/webhook-smoke")
    assert_equal(fetched_webhook["id"], "webhook-smoke", "fetched webhook endpoint id")

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

    rejected_review = request_json(
        base_url,
        "/api/asset_reviews",
        method="POST",
        payload={
            "id": "asset-review-rollback-smoke",
            "assetId": "top-rejected-placeholder",
            "status": "rejected",
            "licenseStatus": "blocked",
            "notes": "Rejected placeholder asset for rollback smoke.",
        },
    )
    assert_equal(rejected_review["status"], "rejected", "rejected asset review status")
    rolled_back_review = request_json(
        base_url,
        "/api/asset_reviews/asset-review-rollback-smoke",
        method="PATCH",
        payload={"action": "rollback", "reviewerId": "user-demo", "notes": "Rolled back rejected asset."},
    )
    assert_equal(rolled_back_review["status"], "archived", "rolled back asset review status")
    assert_equal(rolled_back_review["licenseStatus"], "blocked", "rolled back asset review license status")

    asset_validation = request_json(
        base_url,
        "/api/asset_validations",
        method="POST",
        payload={
            "id": "asset-validation-smoke",
            "assetId": "hair-short-placeholder",
            "checks": [
                {
                    "name": "file_present",
                    "status": "failed",
                    "message": "Placeholder asset file is not present in assets/parts.",
                },
                {"name": "license_recorded", "status": "passed"},
            ],
        },
    )
    assert_equal(asset_validation["status"], "failed", "asset validation status")
    fetched_asset_validation = request_json(base_url, "/api/asset_validations/asset-validation-smoke")
    assert_equal(fetched_asset_validation["id"], "asset-validation-smoke", "fetched asset validation id")

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

    status_update = request_json(
        base_url,
        "/api/status_page_updates",
        method="POST",
        payload={
            "id": "status-update-smoke",
            "incidentId": "incident-smoke",
            "status": "monitoring",
            "message": "Model exports are recovering in the smoke test.",
            "customerImpact": "Delayed exports are catching up.",
        },
    )
    assert_equal(status_update["status"], "monitoring", "created status page update status")

    status_updates = request_json(base_url, "/api/status_page_updates")
    status_update_ids = {item["id"] for item in status_updates.get("statusPageUpdates", [])}
    if "status-update-smoke" not in status_update_ids:
        raise AssertionError("status page updates did not include status-update-smoke")

    fetched_status_update = request_json(base_url, "/api/status_page_updates/status-update-smoke")
    assert_equal(fetched_status_update["incidentId"], "incident-smoke", "fetched status page update incident id")

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
    deleted_face_avatar_status = request_status_json(
        base_url,
        "/api/avatars/from_face_analysis",
        method="POST",
        payload={"avatarId": "face-avatar-deleted", "faceAnalysisJobId": "face-job-smoke"},
    )
    assert_equal(deleted_face_avatar_status, 404, "deleted face analysis avatar create status")

    ai_job = request_json(
        base_url,
        "/api/ai_generation_jobs",
        method="POST",
        payload={
            "id": "ai-job-smoke",
            "avatarConfig": face_avatar,
            "includeRejectedCandidate": True,
            "safeHints": {
                "skinColor": face_avatar["colors"]["skin"],
                "hairColor": face_avatar["colors"]["hair"],
                "facePreset": face_avatar["parts"]["face"],
                "hairPreset": face_avatar["parts"]["hair"],
            },
        },
    )
    assert_equal(ai_job["status"], "succeeded", "ai generation job status")
    if len(ai_job["candidates"]) < 3:
        raise AssertionError("ai generation job did not include multiple candidates")
    approved_candidates = [candidate for candidate in ai_job["candidates"] if candidate["safety"]["status"] == "approved"]
    rejected_candidates = [candidate for candidate in ai_job["candidates"] if candidate["safety"]["status"] == "rejected"]
    for candidate in approved_candidates:
        assert_equal(candidate["safety"]["status"], "approved", f"{candidate['id']} safety status")
    if not rejected_candidates:
        raise AssertionError("ai generation job did not include a rejected candidate")

    ai_avatar = request_json(
        base_url,
        "/api/avatars/from_ai_candidate",
        method="POST",
        payload={"avatarId": "ai-avatar-smoke", "jobId": "ai-job-smoke", "candidateId": "candidate-clean"},
    )
    assert_equal(ai_avatar["source"]["kind"], "ai_generation", "ai avatar source kind")
    rejected_candidate_status = request_status_json(
        base_url,
        "/api/avatars/from_ai_candidate",
        method="POST",
        payload={"avatarId": "ai-avatar-rejected", "jobId": "ai-job-smoke", "candidateId": rejected_candidates[0]["id"]},
    )
    assert_equal(rejected_candidate_status, 404, "rejected ai candidate create status")

    feedback = request_json(
        base_url,
        "/api/recommendation_feedback",
        method="POST",
        payload={
            "id": "feedback-smoke",
            "jobId": "ai-job-smoke",
            "candidateId": "candidate-clean",
            "action": "applied",
        },
    )
    assert_equal(feedback["action"], "applied", "recommendation feedback action")

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

    public_avatar = request_json(base_url, "/api/avatars/smoke-avatar/public")
    assert_equal(public_avatar["avatarId"], "smoke-avatar", "public avatar id")
    assert_equal(public_avatar["visibility"], "public", "public avatar visibility")
    if not public_avatar["publicUrl"].endswith("/avatars/smoke-avatar"):
        raise AssertionError("public avatar URL did not include avatar id")
    if "/api/avatars/smoke-avatar/config" not in public_avatar["configUrl"]:
        raise AssertionError("public avatar config URL did not point to avatar config")

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
    assert_equal(export_job["cacheHit"], False, "first glb export cache hit")
    fetched_export_job = request_json(base_url, f"/api/export_jobs/{export_job['id']}")
    assert_equal(fetched_export_job["id"], export_job["id"], "fetched glb export job id")
    export_jobs = request_json(base_url, "/api/export_jobs")
    if export_job["id"] not in {job["id"] for job in export_jobs.get("exportJobs", [])}:
        raise AssertionError("export jobs did not include created GLB job")
    cached_export_job = request_json(base_url, "/api/export_jobs", method="POST", payload={"avatarConfig": config})
    assert_equal(cached_export_job["cacheHit"], True, "second glb export cache hit")
    assert_equal(cached_export_job["cachedExportJobId"], export_job["id"], "cached glb export source job")

    failed_export_job = request_json(
        base_url,
        "/api/export_jobs",
        method="POST",
        payload={"avatarConfig": config, "simulateFailure": True},
    )
    assert_equal(failed_export_job["status"], "failed", "failed glb export status")
    assert_equal(failed_export_job["errorCode"], "asset_missing", "failed glb export error code")
    assert_equal(failed_export_job["retryable"], True, "failed glb export retryable")
    retried_export_job = request_json(
        base_url,
        f"/api/export_jobs/{failed_export_job['id']}",
        method="PATCH",
        payload={"action": "retry"},
    )
    assert_equal(retried_export_job["status"], "succeeded", "retried glb export status")
    if "modelUrl" not in retried_export_job:
        raise AssertionError("retried export job did not include modelUrl")
    if "errorCode" in retried_export_job:
        raise AssertionError("retried export job still included errorCode")

    vrm_job = request_json(base_url, "/api/vrm_export_jobs", method="POST", payload={"avatarConfig": config})
    assert_equal(vrm_job["status"], "succeeded", "vrm export status")
    if "vrm" not in vrm_job:
        raise AssertionError("vrm export job did not include VRM metadata")
    if len(vrm_job["vrm"]["humanoid"]) < 17:
        raise AssertionError("vrm export job did not include the minimum humanoid bone map")
    assert_equal(vrm_job["vrm"]["meta"]["licenseName"], "repository", "vrm meta license")
    assert_equal(vrm_job["vrm"]["meta"]["commercialUsage"], "allowed", "vrm meta commercial usage")
    fetched_vrm_job = request_json(base_url, f"/api/vrm_export_jobs/{vrm_job['id']}")
    assert_equal(fetched_vrm_job["id"], vrm_job["id"], "fetched vrm export job id")

    usage = request_json(base_url, "/api/usage_events")
    metrics = {event["metric"] for event in usage.get("usageEvents", [])}
    for metric in {"avatar_created", "model_downloaded", "model_exported", "api_request"}:
        if metric not in metrics:
            raise AssertionError(f"usage events did not include {metric}")

    deliveries = request_json(base_url, "/api/webhook_deliveries")
    webhook_deliveries = deliveries.get("webhookDeliveries", [])
    events = {delivery["event"] for delivery in webhook_deliveries}
    for event in {"avatar.created", "model.exported", "asset.reviewed"}:
        if event not in events:
            raise AssertionError(f"webhook deliveries did not include {event}")
    delivery_id = webhook_deliveries[0]["id"]
    retried_delivery = request_json(
        base_url,
        f"/api/webhook_deliveries/{delivery_id}",
        method="PATCH",
        payload={"action": "retry"},
    )
    assert_equal(retried_delivery["status"], "queued", "retried webhook delivery status")
    if retried_delivery["attempt"] <= webhook_deliveries[0]["attempt"]:
        raise AssertionError("retried webhook delivery did not increment attempt")

    paused_webhook = request_json(
        base_url,
        "/api/webhook_endpoints/webhook-smoke",
        method="PATCH",
        payload={"status": "paused"},
    )
    assert_equal(paused_webhook["status"], "paused", "paused webhook endpoint status")

    audit = request_json(base_url, "/api/audit_logs")
    actions = {log["action"] for log in audit.get("auditLogs", [])}
    for action in {
        "asset.reviewed",
        "asset.rollback",
        "app.created",
        "avatar.created",
        "avatar.updated",
        "api_key.created",
        "api_key.revoked",
        "team.member.invited",
        "team.member.role_changed",
        "billing.plan_changed",
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
    metrics = {alert["metric"] for alert in open_alerts}
    if "api_error_rate" not in metrics:
        raise AssertionError("monitoring alerts did not include api_error_rate")
    if "asset_validation_failure" not in metrics:
        raise AssertionError("monitoring alerts did not include asset_validation_failure")

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

    admin_dashboard = request_json(base_url, "/api/admin/dashboard")
    assert_equal(
        admin_dashboard["summary"]["usageEventCount"],
        ops_summary["usageEventCount"],
        "admin dashboard summary usage event count",
    )
    if not admin_dashboard["apps"]:
        raise AssertionError("admin dashboard did not include apps")
    if not admin_dashboard["recentAuditLogs"]:
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
