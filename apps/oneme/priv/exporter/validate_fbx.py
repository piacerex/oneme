#!/usr/bin/env python3
"""Validate the minimal container signature required for an FBX export."""

from __future__ import annotations

import argparse
from pathlib import Path


BINARY_HEADER = b"Kaydara FBX Binary  \x00\x1a\x00"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    args = parser.parse_args()

    data = args.input.read_bytes()
    if data.startswith(BINARY_HEADER):
        print("FBX binary header: valid")
        return 0

    if data.lstrip().startswith(b"; FBX"):
        print("FBX ASCII header: valid")
        return 0

    raise SystemExit("The file does not have a recognized FBX header.")


if __name__ == "__main__":
    raise SystemExit(main())
