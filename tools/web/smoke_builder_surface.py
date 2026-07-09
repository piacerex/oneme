#!/usr/bin/env python3
"""Smoke test the MVP web builder source-level workflow surface."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INDEX_FILE = ROOT / "apps/web/index.html"
APP_FILE = ROOT / "apps/web/src/app.js"
STYLE_FILE = ROOT / "apps/web/styles.css"


def assert_contains(label: str, source: str, tokens: list[str]) -> None:
    missing = [token for token in tokens if token not in source]
    if missing:
        raise AssertionError(f"{label} missing tokens: {', '.join(missing)}")


def main() -> int:
    index = INDEX_FILE.read_text(encoding="utf-8")
    app = APP_FILE.read_text(encoding="utf-8")
    styles = STYLE_FILE.read_text(encoding="utf-8")

    assert_contains(
        "builder HTML",
        index,
        [
            'id="save-avatar"',
            'id="load-avatar"',
            'id="export-glb"',
            'id="export-vrm"',
            'id="get-model-url"',
            'id="download-glb"',
            'id="download-vrm"',
        ],
    )

    assert_contains(
        "builder JS",
        app,
        [
            "function saveAvatar()",
            "function loadLatestAvatar()",
            "function exportGlb()",
            "function exportVrm()",
            "function getAvatarModelUrl()",
            "window.localStorage.setItem(storageKey",
            "getSavedAvatars()",
            "createAvatarModelResponse(",
            "downloadGlbLink.href",
            "downloadVrmLink.href",
            'saveButton.addEventListener("click", saveAvatar)',
            'loadButton.addEventListener("click", loadLatestAvatar)',
            'exportButton.addEventListener("click", exportGlb)',
            'exportVrmButton.addEventListener("click", exportVrm)',
            'getModelUrlButton.addEventListener("click", getAvatarModelUrl)',
        ],
    )

    assert_contains(
        "responsive builder CSS",
        styles,
        [
            ".workspace",
            "grid-template-columns: minmax(0, 1fr) 380px",
            ".preview-stack",
            "grid-template-columns: minmax(260px, 420px) minmax(220px, 320px)",
            ".three-preview",
            "aspect-ratio: 3 / 4",
            ".avatar-preview",
            "@media (max-width: 900px)",
            "grid-template-columns: 1fr",
            ".actions",
            ".panel-heading",
        ],
    )

    print("ok: Web builder surface smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
