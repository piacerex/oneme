#!/usr/bin/env python3
"""Placeholder entrypoint for the future Blender-based avatar composer.

The current Phase 4 MVP exports a valid GLB container in the browser. Once real
part assets exist, this script should be run inside Blender Python to merge
resolved parts into a mesh-backed GLB.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Compose an oneme avatar from resolved parts.")
    parser.add_argument("--config", required=True, help="Path to avatar config JSON.")
    parser.add_argument("--resolved-parts", required=True, help="Path to resolved part records JSON.")
    parser.add_argument("--out", required=True, help="Output GLB path.")
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text())
    resolved_parts = json.loads(Path(args.resolved_parts).read_text())

    summary = {
        "status": "not_implemented",
        "message": "Run the browser MVP exporter until production part assets are available.",
        "avatarId": config.get("avatarId"),
        "partCount": len(resolved_parts),
        "out": args.out,
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
