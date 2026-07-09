#!/usr/bin/env python3
"""Smoke test the local GLB export contract."""

from __future__ import annotations

import copy
import json
import struct
import tempfile
from pathlib import Path

from create_sample_glb import GLB_JSON, GLB_MAGIC, create_glb_bytes, pad_json
from validate_glb import REQUIRED_PART_FIELDS, validate


def read_gltf(path: Path) -> dict:
    data = path.read_bytes()
    json_length = struct.unpack_from("<I", data, 12)[0]
    json_start = 20
    json_end = json_start + json_length
    return json.loads(data[json_start:json_end].decode("utf-8").rstrip(" "))


def write_gltf_as_glb(path: Path, gltf: dict) -> None:
    json_chunk = pad_json(json.dumps(gltf, separators=(",", ":")).encode("utf-8"))
    total_length = 12 + 8 + len(json_chunk)
    path.write_bytes(
        struct.pack("<III", GLB_MAGIC, 2, total_length)
        + struct.pack("<II", len(json_chunk), GLB_JSON)
        + json_chunk
    )


def expect_invalid_missing_resolved_part(path: Path) -> None:
    gltf = read_gltf(path)
    broken = copy.deepcopy(gltf)
    resolved_parts = broken["asset"]["extras"]["oneme"]["resolvedParts"]
    broken["asset"]["extras"]["oneme"]["resolvedParts"] = [
        part for part in resolved_parts if part.get("field") != "hair"
    ]
    write_gltf_as_glb(path, broken)

    try:
        validate(path)
    except ValueError as error:
        if "hair" in str(error):
            return
        raise

    raise AssertionError("invalid GLB without hair resolved part passed validation")


def main() -> int:
    config = {
        "avatarId": "glb-contract-demo",
        "version": "0.1.0",
        "style": "semi_real_lightweight",
        "parts": {
            "baseBody": "base_body.default",
            "face": "face.soft_01",
            "hair": "hair.short_01",
            "top": "top.basic_01",
            "bottom": "bottom.basic_01",
            "shoes": "shoes.basic_01",
            "accessory": "accessory.none",
        },
        "colors": {
            "skin": "#c98f6f",
            "hair": "#2f2118",
        },
    }

    with tempfile.TemporaryDirectory() as directory:
        valid_glb = Path(directory) / "contract-demo.glb"
        invalid_glb = Path(directory) / "missing-hair.glb"
        valid_glb.write_bytes(create_glb_bytes(config))
        invalid_glb.write_bytes(create_glb_bytes(config))

        result = validate(valid_glb)
        if result["avatarId"] != config["avatarId"]:
            raise AssertionError("validated GLB did not report avatar id")
        if result["requiredPartCount"] != len(REQUIRED_PART_FIELDS):
            raise AssertionError("required part count is not reported")
        if result["resolvedPartCount"] < result["requiredPartCount"]:
            raise AssertionError("validated GLB did not include required resolved parts")

        expect_invalid_missing_resolved_part(invalid_glb)

    print("ok: GLB contract smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
