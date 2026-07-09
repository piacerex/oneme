#!/usr/bin/env python3
"""Create a minimal oneme GLB sample for local Phase 4 validation."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A


def pad_json(data: bytes) -> bytes:
    padding = (-len(data)) % 4
    return data + (b" " * padding)


def resolve_avatar_parts(config: dict) -> list[dict]:
    required_fields = ["baseBody", "face", "hair", "top", "bottom", "shoes", "accessory"]
    parts = config.get("parts", {})
    resolved_parts = []

    for field in required_fields:
        part_id = parts.get(field)
        if not part_id:
            raise ValueError(f"missing required avatar part: {field}")

        category = part_id.split(".")[0]
        resolved_parts.append(
            {
                "field": field,
                "partId": part_id,
                "category": category,
                "assetPath": f"assets/parts/{category}/{part_id.replace('.', '-')}.glb",
                "required": True,
                "status": "placeholder",
            }
        )

    return resolved_parts


def create_glb_bytes(config: dict, resolved_parts: list[dict] | None = None) -> bytes:
    resolved = resolved_parts if resolved_parts is not None else resolve_avatar_parts(config)
    gltf = {
        "asset": {
            "version": "2.0",
            "generator": "oneme local MVP exporter",
            "extras": {
                "oneme": {
                    "config": config,
                    "resolvedParts": resolved,
                }
            },
        },
        "scenes": [{"nodes": []}],
        "scene": 0,
        "nodes": [],
    }

    json_chunk = pad_json(json.dumps(gltf, separators=(",", ":")).encode("utf-8"))
    total_length = 12 + 8 + len(json_chunk)
    header = struct.pack("<III", GLB_MAGIC, 2, total_length)
    chunk_header = struct.pack("<II", len(json_chunk), GLB_JSON)
    return header + chunk_header + json_chunk


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a minimal oneme GLB sample.")
    parser.add_argument("--config", default=str(ROOT / "schemas/avatar-config.example.json"))
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text())
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(create_glb_bytes(config))
    print(json.dumps({"file": str(output), "bytes": output.stat().st_size}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
