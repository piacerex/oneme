#!/usr/bin/env python3
"""Validate the minimal GLB contract emitted by the oneme exporter."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A
GLB_BIN = 0x004E4942


def read_gltf(path: Path) -> tuple[dict, list[int]]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("file is too small to be a GLB")

    magic, version, total_length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("invalid GLB magic")
    if version != 2:
        raise ValueError(f"unsupported GLB version: {version}")
    if total_length != len(data):
        raise ValueError("declared GLB length does not match file length")

    offset = 12
    gltf = None
    chunk_types = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        start = offset + 8
        end = start + chunk_length
        if end > len(data):
            raise ValueError("GLB chunk extends past file end")
        body = data[start:end]
        chunk_types.append(chunk_type)
        if chunk_type == GLB_JSON:
            if gltf is not None:
                raise ValueError("GLB contains multiple JSON chunks")
            gltf = json.loads(body.decode("utf-8").rstrip(" "))
        offset = end

    if gltf is None:
        raise ValueError("GLB JSON chunk is missing")
    if GLB_BIN not in chunk_types:
        raise ValueError("GLB binary chunk is missing")
    return gltf, chunk_types


def validate(path: Path, require_vrm: bool) -> dict:
    gltf, chunk_types = read_gltf(path)
    asset = gltf.get("asset", {})
    if asset.get("version") != "2.0":
        raise ValueError("gltf asset version is not 2.0")
    meshes = gltf.get("meshes", [])
    if not isinstance(meshes, list) or not meshes:
        raise ValueError("GLB must contain at least one mesh")

    if require_vrm:
        vrm = gltf.get("extensions", {}).get("VRMC_vrm")
        extras_vrm = asset.get("extras", {}).get("vrm")
        if "VRMC_vrm" not in gltf.get("extensionsUsed", []):
            raise ValueError("VRMC_vrm is not listed in extensionsUsed")
        if not isinstance(vrm, dict) or not isinstance(extras_vrm, dict):
            raise ValueError("VRM metadata is missing")

    return {
        "file": str(path),
        "bytes": path.stat().st_size,
        "meshCount": len(meshes),
        "chunkTypes": chunk_types,
        "vrm": require_vrm,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--require-vrm", action="store_true")
    args = parser.parse_args()

    try:
        result = validate(Path(args.input), args.require_vrm)
    except Exception as error:  # noqa: BLE001
        print(f"invalid: {error}")
        return 1

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
