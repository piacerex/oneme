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

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        parts = path.strip("/").split("/")

        if path == "/health":
            self.send_json({"ok": True, "service": "oneme-api-mock"})
        elif path == "/api/parts":
            self.send_json({"parts": PARTS})
        elif len(parts) == 3 and parts[:2] == ["api", "avatars"]:
            self.send_avatar(parts[2])
        elif len(parts) == 4 and parts[:2] == ["api", "avatars"] and parts[3] == "config":
            self.send_avatar(parts[2])
        elif len(parts) == 4 and parts[:2] == ["api", "avatars"] and parts[3] == "model":
            query = parse_qs(parsed.query)
            self.send_model(parts[2], query.get("format", ["glb"])[0])
        else:
            self.send_error_json(404, "not_found")

    def do_POST(self) -> None:  # noqa: N802
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
            self.send_json(avatar, status=201)
        elif path == "/api/export_jobs":
            payload = self.read_json_body()
            self.send_json(self.create_export_job(payload.get("avatarConfig", DEFAULT_AVATAR), "glb"), status=201)
        elif path == "/api/vrm_export_jobs":
            payload = self.read_json_body()
            self.send_json(self.create_export_job(payload.get("avatarConfig", DEFAULT_AVATAR), "vrm"), status=201)
        else:
            self.send_error_json(404, "not_found")

    def do_PATCH(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        parts = path.strip("/").split("/")

        if len(parts) != 3 or parts[:2] != ["api", "avatars"]:
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
        self.send_json(avatar)

    def send_avatar(self, avatar_id: str) -> None:
        avatar = self.avatars.get(avatar_id)
        if not avatar:
            self.send_error_json(404, "avatar_not_found")
            return
        self.send_json(avatar)

    def send_model(self, avatar_id: str, model_format: str) -> None:
        if avatar_id not in self.avatars:
            self.send_error_json(404, "avatar_not_found")
            return
        if model_format not in {"glb", "vrm"}:
            self.send_error_json(400, "unsupported_model_format")
            return

        self.send_json(
            {
                "avatarId": avatar_id,
                "format": model_format,
                "modelUrl": f"http://localhost:{self.server.server_port}/models/{avatar_id}.{model_format}",
                "exportJobId": f"{model_format}-mock-{avatar_id}",
                "cacheHit": False,
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
        return job

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
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, code: str) -> None:
        self.send_json({"error": code}, status=status)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the oneme API mock server.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), OnemeMockApi)
    print(f"oneme API mock listening on http://{args.host}:{args.port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
