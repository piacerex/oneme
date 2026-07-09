#!/usr/bin/env python3
"""Create a minimal VRM-shaped GLB sample for local Phase 7 validation."""

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


def create_vrm_metadata(config: dict) -> dict:
    avatar_id = config.get("avatarId", "local-demo")
    return {
        "meta": {
            "name": avatar_id,
            "version": config.get("version", "0.1.0"),
            "author": "oneme",
            "contactInformation": "https://github.com/piacerex/oneme",
            "licenseName": "repository",
        },
        "humanoid": {
            "hips": "hips",
            "spine": "spine",
            "chest": "chest",
            "neck": "neck",
            "head": "head",
            "leftUpperArm": "leftUpperArm",
            "leftLowerArm": "leftLowerArm",
            "leftHand": "leftHand",
            "rightUpperArm": "rightUpperArm",
            "rightLowerArm": "rightLowerArm",
            "rightHand": "rightHand",
            "leftUpperLeg": "leftUpperLeg",
            "leftLowerLeg": "leftLowerLeg",
            "leftFoot": "leftFoot",
            "rightUpperLeg": "rightUpperLeg",
            "rightLowerLeg": "rightLowerLeg",
            "rightFoot": "rightFoot",
        },
        "expressions": ["neutral", "happy", "blink", "surprised"],
        "springBones": ["hair", "accessory"],
    }


def create_vrm_bytes(config: dict) -> bytes:
    vrm = create_vrm_metadata(config)
    gltf = {
        "asset": {
            "version": "2.0",
            "generator": "oneme local MVP VRM exporter",
            "extras": {
                "oneme": {"config": config},
                "vrm": vrm,
            },
        },
        "extensionsUsed": ["VRMC_vrm"],
        "extensions": {"VRMC_vrm": vrm},
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
    parser = argparse.ArgumentParser(description="Create a minimal oneme VRM-shaped GLB sample.")
    parser.add_argument("--config", default=str(ROOT / "schemas/avatar-config.example.json"))
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text())
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(create_vrm_bytes(config))
    print(json.dumps({"file": str(output), "bytes": output.stat().st_size}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
