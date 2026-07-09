#!/usr/bin/env python3
"""Smoke test the face-photo-to-avatar workflow surface."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INDEX_FILE = ROOT / "apps/web/index.html"
APP_FILE = ROOT / "apps/web/src/app.js"
THREE_PREVIEW_FILE = ROOT / "apps/web/src/three-preview.js"


def assert_contains(label: str, source: str, tokens: list[str]) -> None:
    missing = [token for token in tokens if token not in source]
    if missing:
        raise AssertionError(f"{label} missing tokens: {', '.join(missing)}")


def main() -> int:
    index = INDEX_FILE.read_text(encoding="utf-8")
    app = APP_FILE.read_text(encoding="utf-8")
    three_preview = THREE_PREVIEW_FILE.read_text(encoding="utf-8")

    assert_contains(
        "face photo HTML",
        index,
        [
            'id="face-consent"',
            'id="face-photo"',
            'id="map-face-texture"',
            'id="analyze-face"',
            'id="clear-face"',
            'id="face-result"',
            'accept="image/*"',
            "Manual creation works without a photo.",
        ],
    )

    assert_contains(
        "face photo workflow JS",
        app,
        [
            "function analyzeFacePhoto()",
            "function clearFacePhoto()",
            "function detectFaceCutout(image)",
            "function drawFacePhotoReference()",
            "function drawMappedFaceTexture(",
            "function traceFaceContourPath(",
            "function estimateFaceMorph(image, crop)",
            "function applyFaceRecommendation(recommendation)",
            "recommendation.faceMorph = estimateFaceMorph(image, faceCutout)",
            'mode: "cutout_overlay"',
            'kind: "face_recommendation"',
            "URL.revokeObjectURL(currentPhotoUrl)",
            "mapFaceTexture.addEventListener",
            'analyzeFaceButton.addEventListener("click", analyzeFacePhoto)',
            'clearFaceButton.addEventListener("click", clearFacePhoto)',
            "window.onemeThreePreview?.sync(cloneConfig())",
        ],
    )

    assert_contains(
        "three preview face sync",
        three_preview,
        [
            "const faceOverlay = new THREE.Mesh",
            "materials.faceTexture.opacity = config.faceTexture?.enabled ? 0.28 : 0.0",
            "head.scale.set(morph.widthScale",
            "faceOverlay.scale.set((morph.widthScale",
            "eyes.position.y",
            "mouth.position.y",
            "avatar.rotation.y = time / 3600",
        ],
    )

    print("ok: Face photo surface smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
