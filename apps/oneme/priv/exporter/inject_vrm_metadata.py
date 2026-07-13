#!/usr/bin/env python3
"""Inject the oneme VRM metadata contract into an existing GLB."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A
HUMANOID_BONES = (
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
)


def pad_json(value: bytes) -> bytes:
    return value + (b" " * ((-len(value)) % 4))


def read_chunks(data: bytes) -> tuple[dict, list[tuple[int, bytes]]]:
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
    chunks: list[tuple[int, bytes]] = []
    gltf: dict | None = None
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        start = offset + 8
        end = start + chunk_length
        if end > len(data):
            raise ValueError("GLB chunk extends past file end")
        chunk = data[start:end]
        if chunk_type == GLB_JSON:
            if gltf is not None:
                raise ValueError("GLB contains multiple JSON chunks")
            gltf = json.loads(chunk.decode("utf-8").rstrip(" "))
        else:
            chunks.append((chunk_type, chunk))
        offset = end

    if gltf is None:
        raise ValueError("GLB JSON chunk is missing")
    return gltf, chunks


def vrm_metadata(config: dict) -> dict:
    name = config.get("name") or config.get("avatarName") or "oneme avatar"
    return {
        "meta": {
            "name": str(name)[:80],
            "version": "0.1.0",
            "author": "oneme",
            "contactInformation": "https://github.com/piacerex/oneme",
            "licenseName": "repository",
            "commercialUsage": "allowed",
        },
        "humanoid": {bone: bone for bone in HUMANOID_BONES},
        "expressions": ["neutral", "happy", "blink", "surprised"],
        "springBones": ["hair", "accessory"],
    }


def write_glb(gltf: dict, chunks: list[tuple[int, bytes]], output: Path) -> None:
    json_chunk = pad_json(json.dumps(gltf, separators=(",", ":"), ensure_ascii=True).encode("utf-8"))
    encoded_chunks = [struct.pack("<II", len(json_chunk), GLB_JSON) + json_chunk]
    encoded_chunks.extend(struct.pack("<II", len(chunk), chunk_type) + chunk for chunk_type, chunk in chunks)
    body = b"".join(encoded_chunks)
    header = struct.pack("<III", GLB_MAGIC, 2, 12 + len(body))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + body)


def inject(source: Path, output: Path, config: dict) -> None:
    gltf, chunks = read_chunks(source.read_bytes())
    metadata = vrm_metadata(config)
    extensions_used = list(gltf.get("extensionsUsed", []))
    if "VRMC_vrm" not in extensions_used:
        extensions_used.append("VRMC_vrm")

    asset = gltf.setdefault("asset", {})
    asset["generator"] = "oneme VRM metadata exporter"
    asset.setdefault("extras", {})["vrm"] = metadata
    gltf["extensionsUsed"] = extensions_used
    gltf.setdefault("extensions", {})["VRMC_vrm"] = metadata
    write_glb(gltf, chunks, output)


def main() -> int:
    parser = argparse.ArgumentParser(description="Add oneme VRM metadata to a GLB.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--config", required=True)
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    inject(Path(args.input), Path(args.output), config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
