#!/usr/bin/env python3
"""Smoke test Unity SDK source-level API surface."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UNITY_LOADER = ROOT / "packages/sdk-unity/Runtime/OnemeAvatarLoader.cs"
UNITY_PACKAGE = ROOT / "packages/sdk-unity/package.json"


def main() -> int:
    source = UNITY_LOADER.read_text(encoding="utf-8")
    expected_tokens = [
        "OnemeModelResponse",
        "public string avatarId;",
        "public string format;",
        "public string modelUrl;",
        "public string exportJobId;",
        "public bool cacheHit;",
        "OnemeAnimationCompatibilityResponse",
        "public string[] requiredHumanoidBones;",
        "public string[] missingHumanoidBones;",
        "public string[] expressions;",
        "public OnemeModelResponse LastModelResponse",
        "public OnemeAnimationCompatibilityResponse LastAnimationCompatibility",
        "public string ApiBaseUrl",
        "public string Format",
        "LoadAnimationCompatibility()",
        "BuildModelUrl()",
        "BuildAnimationCompatibilityUrl()",
        "JsonUtility.FromJson<OnemeModelResponse>",
        "JsonUtility.FromJson<OnemeAnimationCompatibilityResponse>",
        "/api/avatars/{escapedAvatarId}/model?format={escapedFormat}",
        "/api/avatars/{escapedAvatarId}/animation_compat?format={escapedFormat}",
    ]
    missing = [token for token in expected_tokens if token not in source]
    if missing:
        raise AssertionError(f"Unity SDK missing API surface tokens: {', '.join(missing)}")

    package = json.loads(UNITY_PACKAGE.read_text(encoding="utf-8"))
    if package.get("name") != "com.oneme.sdk":
        raise AssertionError("Unity SDK package name changed unexpectedly")

    print("ok: Unity SDK smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
