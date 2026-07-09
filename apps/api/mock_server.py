#!/usr/bin/env python3
"""Small dependency-free API mock for the oneme roadmap contracts."""

from __future__ import annotations

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_AVATAR = json.loads((ROOT / "schemas/avatar-config.example.json").read_text())

PARTS = [
    {"id": "base_body.default", "category": "baseBody", "label": "Default Body"},
    {"id": "face.soft_01", "category": "face", "label": "Soft Face"},
    {"id": "face.sharp_01", "category": "face", "label": "Sharp Face"},
    {"id": "face.round_01", "category": "face", "label": "Round Face"},
    {"id": "hair.short_01", "category": "hair", "label": "Short Hair"},
    {"id": "hair.medium_01", "category": "hair", "label": "Medium Hair"},
    {"id": "hair.long_01", "category": "hair", "label": "Long Hair"},
    {"id": "top.basic_01", "category": "top", "label": "Basic Tee"},
    {"id": "bottom.basic_01", "category": "bottom", "label": "Basic Pants"},
    {"id": "shoes.basic_01", "category": "shoes", "label": "Basic Shoes"},
    {"id": "accessory.none", "category": "accessory", "label": "None"},
]


def now_id(prefix: str) -> str:
    return f"{prefix}-{int(time.time() * 1000)}"


class OnemeMockApi(BaseHTTPRequestHandler):
    avatars: dict[str, dict] = {DEFAULT_AVATAR["avatarId"]: DEFAULT_AVATAR}
    asset_reviews: dict[str, dict] = {}
    usage_events: list[dict] = []
    audit_logs: list[dict] = []
    monitoring_alerts: list[dict] = []
    incidents: dict[str, dict] = {}
    legal_records: dict[str, dict] = {}
    webhook_endpoints: dict[str, dict] = {}
    webhook_deliveries: list[dict] = []
    rate_limits: dict[str, dict] = {}
    rate_limit_window_seconds = 60
    rate_limit_max_requests = 600

    def do_GET(self) -> None:  # noqa: N802
        if not self.check_rate_limit():
            return

        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        parts = path.strip("/").split("/")

        if path == "/health":
            self.send_json({"ok": True, "service": "oneme-api-mock"})
        elif path == "/api/parts":
            self.record_usage("api_request", {"endpoint": "/api/parts"})
            self.send_json({"parts": PARTS})
        elif path == "/api/usage_events":
            self.send_json({"usageEvents": self.usage_events})
        elif path == "/api/audit_logs":
            self.send_json({"auditLogs": self.audit_logs})
        elif path == "/api/monitoring_alerts":
            self.send_json({"monitoringAlerts": self.monitoring_alerts})
        elif path == "/api/incidents":
            self.send_json({"incidents": list(self.incidents.values())})
        elif path == "/api/legal_records":
            self.send_json({"legalRecords": list(self.legal_records.values())})
        elif path == "/api/ops/summary":
            self.send_ops_summary()
        elif path == "/api/asset_reviews":
            self.send_json({"assetReviews": list(self.asset_reviews.values())})
        elif path == "/api/webhook_deliveries":
            self.send_json({"webhookDeliveries": self.webhook_deliveries})
        elif len(parts) == 3 and parts[:2] == ["api", "asset_reviews"]:
            self.send_asset_review(parts[2])
        elif len(parts) == 3 and parts[:2] == ["api", "incidents"]:
            self.send_incident(parts[2])
        elif len(parts) == 3 and parts[:2] == ["api", "legal_records"]:
            self.send_legal_record(parts[2])
        elif len(parts) == 3 and parts[:2] == ["api", "avatars"]:
            self.record_usage("api_request", {"endpoint": "/api/avatars/:id", "avatarId": parts[2]})
            self.send_avatar(parts[2])
        elif len(parts) == 4 and parts[:2] == ["api", "avatars"] and parts[3] == "config":
            self.record_usage("api_request", {"endpoint": "/api/avatars/:id/config", "avatarId": parts[2]})
            self.send_avatar(parts[2])
        elif len(parts) == 4 and parts[:2] == ["api", "avatars"] and parts[3] == "model":
            query = parse_qs(parsed.query)
            self.send_model(parts[2], query.get("format", ["glb"])[0])
        elif len(parts) == 4 and parts[:2] == ["api", "avatars"] and parts[3] == "animation_compat":
            query = parse_qs(parsed.query)
            self.send_animation_compat(parts[2], query.get("format", ["vrm"])[0])
        else:
            self.send_error_json(404, "not_found")

    def do_POST(self) -> None:  # noqa: N802
        if not self.check_rate_limit():
            return

        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/api/avatars":
            payload = self.read_json_body()
            config = payload.get("avatarConfig", payload)
            avatar = {**DEFAULT_AVATAR, **config}
            avatar["parts"] = {**DEFAULT_AVATAR["parts"], **avatar.get("parts", {})}
            avatar["colors"] = {**DEFAULT_AVATAR["colors"], **avatar.get("colors", {})}
            avatar["avatarId"] = avatar.get("avatarId") or now_id("avatar")
            self.avatars[avatar["avatarId"]] = avatar
            self.record_usage("avatar_created", {"avatarId": avatar["avatarId"]})
            self.record_audit("avatar.created", "avatar", avatar["avatarId"], {"source": "api_mock"})
            self.queue_webhooks("avatar.created", {"avatarId": avatar["avatarId"], "config": avatar})
            self.send_json(avatar, status=201)
        elif path == "/api/webhook_endpoints":
            payload = self.read_json_body()
            endpoint = {
                "id": payload.get("id") or now_id("webhook"),
                "teamId": payload.get("teamId", "team-demo"),
                "appId": payload.get("appId", "app-demo"),
                "url": payload.get("url", "https://example.com/oneme/webhooks"),
                "events": payload.get("events", ["avatar.created", "model.exported", "export.failed"]),
                "status": payload.get("status", "active"),
                "createdAt": "2026-07-09T00:00:00.000Z",
            }
            self.webhook_endpoints[endpoint["id"]] = endpoint
            self.record_audit(
                "webhook_endpoint.created",
                "webhook_endpoint",
                endpoint["id"],
                {"events": endpoint["events"], "url": endpoint["url"]},
            )
            self.send_json(endpoint, status=201)
        elif path == "/api/asset_reviews":
            payload = self.read_json_body()
            review = {
                "id": payload.get("id") or now_id("asset-review"),
                "assetId": payload.get("assetId", "asset-demo"),
                "teamId": payload.get("teamId", "team-demo"),
                "status": payload.get("status", "submitted"),
                "licenseStatus": payload.get("licenseStatus", "needs_review"),
                "notes": payload.get("notes", ""),
                "createdAt": "2026-07-09T00:00:00.000Z",
                "submittedAt": payload.get("submittedAt", "2026-07-09T00:00:00.000Z"),
            }
            self.asset_reviews[review["id"]] = review
            self.record_audit("asset.reviewed", "asset", review["assetId"], {"status": review["status"]})
            self.queue_webhooks("asset.reviewed", {"assetReview": review})
            self.send_json(review, status=201)
        elif path == "/api/incidents":
            payload = self.read_json_body()
            incident = {
                "id": payload.get("id") or now_id("incident"),
                "severity": payload.get("severity", "major"),
                "status": payload.get("status", "investigating"),
                "summary": payload.get("summary", "Operational incident"),
                "affectedTeams": payload.get("affectedTeams", ["team-demo"]),
                "affectedApps": payload.get("affectedApps", ["app-demo"]),
                "recoveryActions": payload.get("recoveryActions", ["publish_status_update"]),
                "customerImpact": payload.get("customerImpact", "Impact is under investigation."),
                "detectedAt": payload.get("detectedAt", "2026-07-09T00:00:00.000Z"),
            }
            if "resolvedAt" in payload:
                incident["resolvedAt"] = payload["resolvedAt"]
            self.incidents[incident["id"]] = incident
            self.record_audit("incident.created", "incident", incident["id"], {"status": incident["status"]})
            self.send_json(incident, status=201)
        elif path == "/api/legal_records":
            payload = self.read_json_body()
            record = {
                "id": payload.get("id") or now_id("legal"),
                "kind": payload.get("kind", "asset_license"),
                "version": payload.get("version", "2026-07-09"),
                "status": payload.get("status", "draft"),
                "effectiveAt": payload.get("effectiveAt", "2026-07-09T00:00:00.000Z"),
            }
            for key in ("sourceUrl", "usageRights", "retentionDays"):
                if key in payload:
                    record[key] = payload[key]
            self.legal_records[record["id"]] = record
            self.record_audit("legal_record.created", "legal_record", record["id"], {"kind": record["kind"]})
            self.send_json(record, status=201)
        elif path == "/api/export_jobs":
            payload = self.read_json_body()
            self.send_json(self.create_export_job(payload.get("avatarConfig", DEFAULT_AVATAR), "glb"), status=201)
        elif path == "/api/vrm_export_jobs":
            payload = self.read_json_body()
            self.send_json(self.create_export_job(payload.get("avatarConfig", DEFAULT_AVATAR), "vrm"), status=201)
        else:
            self.send_error_json(404, "not_found")

    def do_PATCH(self) -> None:  # noqa: N802
        if not self.check_rate_limit():
            return

        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        parts = path.strip("/").split("/")

        if len(parts) != 3 or parts[:2] != ["api", "avatars"]:
            if len(parts) == 3 and parts[:2] == ["api", "asset_reviews"]:
                self.patch_asset_review(parts[2])
                return
            if len(parts) == 3 and parts[:2] == ["api", "monitoring_alerts"]:
                self.patch_monitoring_alert(parts[2])
                return
            if len(parts) == 3 and parts[:2] == ["api", "incidents"]:
                self.patch_incident(parts[2])
                return
            if len(parts) == 3 and parts[:2] == ["api", "legal_records"]:
                self.patch_legal_record(parts[2])
                return
            self.send_error_json(404, "not_found")
            return

        avatar = self.avatars.get(parts[2])
        if not avatar:
            self.send_error_json(404, "avatar_not_found")
            return

        patch = self.read_json_body()
        avatar.update(patch)
        if "parts" in patch:
            avatar["parts"] = {**DEFAULT_AVATAR["parts"], **patch["parts"]}
        if "colors" in patch:
            avatar["colors"] = {**DEFAULT_AVATAR["colors"], **patch["colors"]}
        self.avatars[parts[2]] = avatar
        self.record_usage("api_request", {"endpoint": "/api/avatars/:id", "method": "PATCH", "avatarId": parts[2]})
        self.record_audit("avatar.updated", "avatar", parts[2], {"fields": sorted(patch.keys())})
        self.send_json(avatar)

    def patch_asset_review(self, review_id: str) -> None:
        review = self.asset_reviews.get(review_id)
        if not review:
            self.send_error_json(404, "asset_review_not_found")
            return

        patch = self.read_json_body()
        review.update(patch)
        if "decision" in patch or "status" in patch:
            review["reviewerId"] = patch.get("reviewerId", review.get("reviewerId", "user-demo"))
            review["reviewedAt"] = patch.get("reviewedAt", "2026-07-09T00:00:01.000Z")
        self.asset_reviews[review_id] = review
        self.record_audit(
            "asset.reviewed",
            "asset",
            review["assetId"],
            {"status": review["status"], "decision": review.get("decision")},
        )
        self.queue_webhooks("asset.reviewed", {"assetReview": review})
        self.send_json(review)

    def patch_monitoring_alert(self, alert_id: str) -> None:
        alert = next((item for item in self.monitoring_alerts if item["id"] == alert_id), None)
        if not alert:
            self.send_error_json(404, "monitoring_alert_not_found")
            return

        patch = self.read_json_body()
        for key in ("status", "severity", "runbookUrl", "resolvedAt"):
            if key in patch:
                alert[key] = patch[key]
        if alert.get("status") == "resolved" and "resolvedAt" not in alert:
            alert["resolvedAt"] = "2026-07-09T00:00:01.000Z"
        self.send_json(alert)

    def patch_incident(self, incident_id: str) -> None:
        incident = self.incidents.get(incident_id)
        if not incident:
            self.send_error_json(404, "incident_not_found")
            return

        patch = self.read_json_body()
        for key in (
            "severity",
            "status",
            "summary",
            "affectedTeams",
            "affectedApps",
            "recoveryActions",
            "customerImpact",
            "resolvedAt",
        ):
            if key in patch:
                incident[key] = patch[key]
        if incident.get("status") == "resolved" and "resolvedAt" not in incident:
            incident["resolvedAt"] = "2026-07-09T00:00:01.000Z"
        self.incidents[incident_id] = incident
        self.record_audit("incident.updated", "incident", incident_id, {"status": incident["status"]})
        self.send_json(incident)

    def patch_legal_record(self, record_id: str) -> None:
        record = self.legal_records.get(record_id)
        if not record:
            self.send_error_json(404, "legal_record_not_found")
            return

        patch = self.read_json_body()
        for key in ("kind", "version", "status", "sourceUrl", "usageRights", "retentionDays", "effectiveAt"):
            if key in patch:
                record[key] = patch[key]
        self.legal_records[record_id] = record
        self.record_audit("legal_record.updated", "legal_record", record_id, {"status": record["status"]})
        self.send_json(record)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_common_headers()
        self.end_headers()

    def check_rate_limit(self) -> bool:
        key = self.get_api_key()
        now = time.time()
        bucket = self.rate_limits.get(key)
        if not bucket or now >= bucket["resetAt"]:
            bucket = {
                "count": 0,
                "resetAt": now + self.rate_limit_window_seconds,
            }

        remaining = self.rate_limit_max_requests - bucket["count"]
        if remaining <= 0:
            self.rate_limits[key] = bucket
            self.rate_limit_headers = {
                "limit": self.rate_limit_max_requests,
                "remaining": 0,
                "reset": int(bucket["resetAt"]),
            }
            self.send_error_json(429, "rate_limited")
            return False

        bucket["count"] += 1
        self.rate_limits[key] = bucket
        self.rate_limit_headers = {
            "limit": self.rate_limit_max_requests,
            "remaining": self.rate_limit_max_requests - bucket["count"],
            "reset": int(bucket["resetAt"]),
        }
        return True

    def get_api_key(self) -> str:
        parsed = urlparse(self.path)
        query_key = parse_qs(parsed.query).get("api_key", [""])[0]
        return self.headers.get("x-oneme-api-key") or query_key or "anonymous"

    def send_avatar(self, avatar_id: str) -> None:
        avatar = self.avatars.get(avatar_id)
        if not avatar:
            self.send_error_json(404, "avatar_not_found")
            return
        self.send_json(avatar)

    def send_asset_review(self, review_id: str) -> None:
        review = self.asset_reviews.get(review_id)
        if not review:
            self.send_error_json(404, "asset_review_not_found")
            return
        self.send_json(review)

    def send_incident(self, incident_id: str) -> None:
        incident = self.incidents.get(incident_id)
        if not incident:
            self.send_error_json(404, "incident_not_found")
            return
        self.send_json(incident)

    def send_legal_record(self, record_id: str) -> None:
        record = self.legal_records.get(record_id)
        if not record:
            self.send_error_json(404, "legal_record_not_found")
            return
        self.send_json(record)

    def send_ops_summary(self) -> None:
        pending_review_statuses = {"draft", "submitted"}
        open_incident_statuses = {"investigating", "mitigating"}
        self.send_json(
            {
                "teamId": "team-demo",
                "appId": "app-demo",
                "usageEventCount": len(self.usage_events),
                "openAlertCount": sum(1 for alert in self.monitoring_alerts if alert["status"] != "resolved"),
                "openIncidentCount": sum(
                    1 for incident in self.incidents.values() if incident["status"] in open_incident_statuses
                ),
                "pendingAssetReviewCount": sum(
                    1 for review in self.asset_reviews.values() if review["status"] in pending_review_statuses
                ),
                "webhookDeliveryCount": len(self.webhook_deliveries),
                "activeLegalRecordCount": sum(
                    1 for record in self.legal_records.values() if record["status"] == "active"
                ),
                "generatedAt": "2026-07-09T00:00:00.000Z",
            }
        )

    def send_model(self, avatar_id: str, model_format: str) -> None:
        if avatar_id not in self.avatars:
            self.send_error_json(404, "avatar_not_found")
            return
        if model_format not in {"glb", "vrm"}:
            self.send_error_json(400, "unsupported_model_format")
            return

        self.record_usage("model_downloaded", {"avatarId": avatar_id, "format": model_format})
        self.send_json(
            {
                "avatarId": avatar_id,
                "format": model_format,
                "modelUrl": f"http://localhost:{self.server.server_port}/models/{avatar_id}.{model_format}",
                "exportJobId": f"{model_format}-mock-{avatar_id}",
                "cacheHit": False,
            }
        )

    def send_animation_compat(self, avatar_id: str, model_format: str) -> None:
        if avatar_id not in self.avatars:
            self.send_error_json(404, "avatar_not_found")
            return
        if model_format != "vrm":
            self.send_error_json(400, "unsupported_animation_format")
            return

        self.record_usage("api_request", {"endpoint": "/api/avatars/:id/animation_compat", "avatarId": avatar_id})
        self.send_json(
            {
                "format": "vrm",
                "status": "contract_ready",
                "requiredHumanoidBones": [
                    "hips",
                    "spine",
                    "chest",
                    "neck",
                    "head",
                    "leftUpperArm",
                    "leftLowerArm",
                    "leftHand",
                    "rightUpperArm",
                    "rightLowerArm",
                    "rightHand",
                    "leftUpperLeg",
                    "leftLowerLeg",
                    "leftFoot",
                    "rightUpperLeg",
                    "rightLowerLeg",
                    "rightFoot",
                ],
                "missingHumanoidBones": [],
                "expressions": ["neutral", "happy", "blink", "surprised"],
                "notes": [
                    "MVP VRM exports include humanoid metadata.",
                    "Runtime animation requires replacing the placeholder scene with rigged geometry.",
                ],
            }
        )

    def create_export_job(self, avatar_config: dict, model_format: str) -> dict:
        avatar_id = avatar_config.get("avatarId", DEFAULT_AVATAR["avatarId"])
        job = {
            "id": now_id(f"{model_format}-export"),
            "status": "succeeded",
            "avatarConfig": avatar_config,
            "modelUrl": f"http://localhost:{self.server.server_port}/models/{avatar_id}.{model_format}",
            "createdAt": "2026-07-09T00:00:00.000Z",
            "finishedAt": "2026-07-09T00:00:01.000Z",
        }
        if model_format == "glb":
            job["cacheKey"] = f"mock-{avatar_id}"
            job["cacheHit"] = False
        else:
            job["vrm"] = {
                "meta": {"name": avatar_id, "version": avatar_config.get("version", "0.1.0")},
                "humanoid": {"hips": "hips", "spine": "spine", "head": "head"},
                "expressions": ["neutral", "happy", "blink", "surprised"],
                "springBones": ["hair", "accessory"],
            }
        self.record_usage("model_exported", {"avatarId": avatar_id, "format": model_format, "exportJobId": job["id"]})
        self.record_audit("model.exported", "export_job", job["id"], {"avatarId": avatar_id, "format": model_format})
        self.queue_webhooks("model.exported", {"avatarId": avatar_id, "format": model_format, "exportJobId": job["id"]})
        return job

    def record_usage(self, metric: str, metadata: dict) -> None:
        self.usage_events.append(
            {
                "id": now_id("usage"),
                "teamId": "team-demo",
                "appId": "app-demo",
                "apiKeyId": "key-demo",
                "metric": metric,
                "quantity": 1,
                "metadata": metadata,
                "occurredAt": "2026-07-09T00:00:00.000Z",
            }
        )

    def record_audit(self, action: str, target_type: str, target_id: str, metadata: dict) -> None:
        self.audit_logs.append(
            {
                "id": now_id("audit"),
                "teamId": "team-demo",
                "actorId": self.get_api_key(),
                "action": action,
                "targetType": target_type,
                "targetId": target_id,
                "metadata": metadata,
                "createdAt": "2026-07-09T00:00:00.000Z",
            }
        )

    def record_alert(self, severity: str, metric: str, value: float = 1, threshold: float = 1) -> None:
        self.monitoring_alerts.append(
            {
                "id": now_id("alert"),
                "teamId": "team-demo",
                "appId": "app-demo",
                "severity": severity,
                "metric": metric,
                "status": "open",
                "value": value,
                "threshold": threshold,
                "runbookUrl": "https://example.com/runbooks/oneme-api-mock",
                "createdAt": "2026-07-09T00:00:00.000Z",
            }
        )

    def queue_webhooks(self, event: str, payload: dict) -> None:
        for endpoint in self.webhook_endpoints.values():
            if endpoint["status"] != "active" or event not in endpoint["events"]:
                continue
            self.webhook_deliveries.append(
                {
                    "id": now_id("delivery"),
                    "endpointId": endpoint["id"],
                    "event": event,
                    "payload": payload,
                    "status": "queued",
                    "attempt": 1,
                    "createdAt": "2026-07-09T00:00:00.000Z",
                }
            )

    def read_json_body(self) -> dict:
        length = int(self.headers.get("content-length", "0"))
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except json.JSONDecodeError:
            self.send_error_json(400, "invalid_json")
            return {}

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_common_headers()
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, code: str) -> None:
        if status >= 400:
            self.record_alert("warning" if status < 500 else "critical", "api_error_rate")
        self.send_json({"error": code}, status=status)

    def send_common_headers(self) -> None:
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-methods", "GET, POST, PATCH, OPTIONS")
        self.send_header("access-control-allow-headers", "content-type, accept, x-oneme-api-key")
        rate_limit = getattr(self, "rate_limit_headers", None)
        if rate_limit:
            self.send_header("x-ratelimit-limit", str(rate_limit["limit"]))
            self.send_header("x-ratelimit-remaining", str(rate_limit["remaining"]))
            self.send_header("x-ratelimit-reset", str(rate_limit["reset"]))


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the oneme API mock server.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--rate-limit", type=int, default=600)
    parser.add_argument("--rate-limit-window", type=int, default=60)
    args = parser.parse_args()

    OnemeMockApi.rate_limits = {}
    OnemeMockApi.asset_reviews = {}
    OnemeMockApi.audit_logs = []
    OnemeMockApi.monitoring_alerts = []
    OnemeMockApi.incidents = {}
    OnemeMockApi.legal_records = {}
    OnemeMockApi.webhook_endpoints = {}
    OnemeMockApi.webhook_deliveries = []
    OnemeMockApi.rate_limit_max_requests = args.rate_limit
    OnemeMockApi.rate_limit_window_seconds = args.rate_limit_window

    server = ThreadingHTTPServer((args.host, args.port), OnemeMockApi)
    print(f"oneme API mock listening on http://{args.host}:{args.port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
