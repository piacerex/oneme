#!/usr/bin/env python3
"""Smoke test the local VRM export contract."""

from __future__ import annotations

import copy
import json
import struct
import tempfile
from pathlib import Path

from create_sample_vrm import GLB_JSON, GLB_MAGIC, create_vrm_bytes, pad_json
from validate_vrm import (
    REQUIRED_EXPRESSIONS,
    REQUIRED_HUMANOID_BONES,
    REQUIRED_META_FIELDS,
    read_gltf,
    validate,
)


def write_vrm(path: Path, config: dict) -> None:
    path.write_bytes(create_vrm_bytes(config))


def write_gltf_as_glb(path: Path, gltf: dict) -> None:
    json_chunk = pad_json(json.dumps(gltf, separators=(",", ":")).encode("utf-8"))
    total_length = 12 + 8 + len(json_chunk)
    path.write_bytes(
        struct.pack("<III", GLB_MAGIC, 2, total_length)
        + struct.pack("<II", len(json_chunk), GLB_JSON)
        + json_chunk
    )


def expect_invalid_missing_bone(path: Path) -> None:
    gltf, _, _ = read_gltf(path)
    vrm = copy.deepcopy(gltf["extensions"]["VRMC_vrm"])
    vrm["humanoid"].pop("head")
    gltf["extensions"]["VRMC_vrm"] = vrm
    gltf["asset"]["extras"]["vrm"] = vrm
    write_gltf_as_glb(path, gltf)

    try:
        validate(path)
    except ValueError as error:
        if "head" in str(error):
            return
        raise

    raise AssertionError("invalid VRM without head bone passed validation")


def main() -> int:
    config = {
        "avatarId": "contract-demo",
        "version": "0.1.0",
        "parts": {},
        "colors": {},
    }

    with tempfile.TemporaryDirectory() as directory:
        valid_vrm = Path(directory) / "contract-demo.vrm"
        invalid_vrm = Path(directory) / "missing-head.vrm"
        write_vrm(valid_vrm, config)
        result = validate(valid_vrm)

        if result["requiredHumanoidBoneCount"] != len(REQUIRED_HUMANOID_BONES):
            raise AssertionError("required humanoid bone count is not reported")
        if result["requiredExpressionCount"] != len(REQUIRED_EXPRESSIONS):
            raise AssertionError("required expression count is not reported")

        missing_meta = REQUIRED_META_FIELDS.difference(result["metaFields"])
        if missing_meta:
            raise AssertionError(f"meta fields missing from valid sample: {sorted(missing_meta)}")

        write_vrm(invalid_vrm, config)
        expect_invalid_missing_bone(invalid_vrm)

    print("ok: VRM contract smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
