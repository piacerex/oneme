#!/usr/bin/env python3
"""Validate the minimal VRM-shaped GLB used by oneme MVP exports."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A


def read_u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def read_gltf(path: Path) -> tuple[dict, int, int]:
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

    return json.loads(data[json_start:json_end].decode("utf-8").rstrip(" ")), len(data), json_length


def validate(path: Path) -> dict:
    gltf, byte_length, json_length = read_gltf(path)
    asset = gltf.get("asset", {})
    if asset.get("version") != "2.0":
        raise ValueError("gltf asset version is not 2.0")

    extras_vrm = asset.get("extras", {}).get("vrm")
    extension_vrm = gltf.get("extensions", {}).get("VRMC_vrm")
    vrm = extension_vrm or extras_vrm
    if not isinstance(vrm, dict):
        raise ValueError("missing VRM metadata in asset.extras.vrm or extensions.VRMC_vrm")

    humanoid = vrm.get("humanoid", {})
    expressions = vrm.get("expressions", [])
    if not isinstance(humanoid, dict) or not humanoid:
        raise ValueError("VRM humanoid bone map is missing")
    if not isinstance(expressions, list) or not expressions:
        raise ValueError("VRM expression presets are missing")

    return {
        "file": str(path),
        "bytes": byte_length,
        "jsonChunkBytes": json_length,
        "generator": asset.get("generator"),
        "hasVrmExtras": isinstance(extras_vrm, dict),
        "hasVrmExtension": isinstance(extension_vrm, dict),
        "humanoidBoneCount": len(humanoid),
        "expressionCount": len(expressions),
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_vrm.py path/to/avatar.vrm", file=sys.stderr)
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
