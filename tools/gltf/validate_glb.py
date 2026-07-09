#!/usr/bin/env python3
"""Validate the minimal GLB structure used by oneme MVP exports."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A
REQUIRED_PART_FIELDS = {"baseBody", "face", "hair", "top", "bottom", "shoes", "accessory"}


def read_u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def validate(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("file is too small to be a GLB")

    magic = read_u32(data, 0)
    version = read_u32(data, 4)
    total_length = read_u32(data, 8)

    if magic != GLB_MAGIC:
        raise ValueError("invalid GLB magic")
    if version != 2:
        raise ValueError(f"unsupported GLB version: {version}")
    if total_length != len(data):
        raise ValueError(f"declared length {total_length} does not match file length {len(data)}")

    json_length = read_u32(data, 12)
    chunk_type = read_u32(data, 16)
    if chunk_type != GLB_JSON:
        raise ValueError("first chunk is not JSON")

    json_start = 20
    json_end = json_start + json_length
    if json_end > len(data):
        raise ValueError("JSON chunk extends past end of file")

    gltf = json.loads(data[json_start:json_end].decode("utf-8").rstrip(" "))
    asset = gltf.get("asset", {})
    if asset.get("version") != "2.0":
        raise ValueError("gltf asset version is not 2.0")

    oneme = asset.get("extras", {}).get("oneme")
    if not isinstance(oneme, dict):
        raise ValueError("missing oneme export metadata in asset.extras.oneme")

    config = oneme.get("config")
    resolved_parts = oneme.get("resolvedParts")
    if not isinstance(config, dict):
        raise ValueError("missing avatar config in asset.extras.oneme.config")
    if not isinstance(resolved_parts, list) or not resolved_parts:
        raise ValueError("missing resolved parts in asset.extras.oneme.resolvedParts")

    resolved_fields = {part.get("field") for part in resolved_parts if isinstance(part, dict)}
    missing_fields = sorted(REQUIRED_PART_FIELDS.difference(resolved_fields))
    if missing_fields:
        raise ValueError(f"resolved parts are missing required fields: {', '.join(missing_fields)}")

    unresolved = [
        part.get("partId", part.get("field", "unknown"))
        for part in resolved_parts
        if isinstance(part, dict) and part.get("required") is True and not part.get("assetPath")
    ]
    if unresolved:
        raise ValueError(f"required resolved parts are missing asset paths: {', '.join(unresolved)}")

    return {
        "file": str(path),
        "bytes": len(data),
        "jsonChunkBytes": json_length,
        "generator": asset.get("generator"),
        "hasOnemeExtras": True,
        "avatarId": config.get("avatarId"),
        "resolvedPartCount": len(resolved_parts),
        "requiredPartCount": len(REQUIRED_PART_FIELDS),
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_glb.py path/to/avatar.glb", file=sys.stderr)
        return 2

    try:
        result = validate(Path(sys.argv[1]))
    except Exception as error:  # noqa: BLE001
        print(f"invalid: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
