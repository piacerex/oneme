#!/usr/bin/env python3
"""Smoke test Phase 0 asset inventory and license coverage."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INVENTORY_FILE = ROOT / "docs/asset-inventory.md"
REQUIRED_COLUMNS = ["Asset ID", "Category", "Source", "License", "Author", "Format", "Status", "Notes"]
REQUIRED_MESH_CATEGORIES = {"base_body", "face", "hair", "top", "bottom", "shoes", "accessory"}
DISALLOWED_LICENSE_WORDS = {"unknown", "forbidden", "non-commercial", "noncommercial"}
ALLOWED_FORMATS = {"glb", "vrm", "texture", "json"}
ALLOWED_STATUSES = {"planned", "review", "approved", "rejected", "archived"}


def parse_table(markdown: str) -> list[dict[str, str]]:
    lines = [line.strip() for line in markdown.splitlines() if line.strip().startswith("|")]
    header_index = next(
        (
            index
            for index, line in enumerate(lines)
            if all(column in line for column in REQUIRED_COLUMNS)
        ),
        None,
    )
    if header_index is None:
        raise AssertionError("asset inventory table header was not found")

    headers = split_row(lines[header_index])
    missing_columns = [column for column in REQUIRED_COLUMNS if column not in headers]
    if missing_columns:
        raise AssertionError(f"asset inventory missing columns: {', '.join(missing_columns)}")

    rows = []
    for line in lines[header_index + 2 :]:
        values = split_row(line)
        if len(values) != len(headers):
            continue
        rows.append(dict(zip(headers, values, strict=True)))
    return rows


def split_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip("|").split("|")]


def main() -> int:
    rows = parse_table(INVENTORY_FILE.read_text(encoding="utf-8"))
    if not rows:
        raise AssertionError("asset inventory has no asset rows")

    seen_ids = set()
    categories = set()
    for row in rows:
        asset_id = row["Asset ID"]
        if asset_id in seen_ids:
            raise AssertionError(f"duplicate asset id: {asset_id}")
        seen_ids.add(asset_id)

        for column in REQUIRED_COLUMNS:
            if not row[column]:
                raise AssertionError(f"{asset_id} has empty {column}")

        license_value = row["License"].lower()
        if any(word in license_value for word in DISALLOWED_LICENSE_WORDS):
            raise AssertionError(f"{asset_id} has disallowed license: {row['License']}")
        if row["Format"] not in ALLOWED_FORMATS:
            raise AssertionError(f"{asset_id} has unsupported format: {row['Format']}")
        if row["Status"] not in ALLOWED_STATUSES:
            raise AssertionError(f"{asset_id} has unsupported status: {row['Status']}")
        categories.add(row["Category"])

    missing_categories = sorted(REQUIRED_MESH_CATEGORIES.difference(categories))
    if missing_categories:
        raise AssertionError(f"asset inventory missing categories: {', '.join(missing_categories)}")

    print("ok: Asset inventory smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
