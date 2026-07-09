#!/usr/bin/env python3
"""Validate schema examples with the repository's supported JSON Schema subset."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "schemas"


class ValidationError(ValueError):
    """Raised when an example does not match its schema."""


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def resolve_ref(schema: dict, ref: str) -> dict:
    prefix = "#/$defs/"
    if not ref.startswith(prefix):
        raise ValidationError(f"unsupported $ref: {ref}")

    name = ref.removeprefix(prefix)
    try:
        target = schema["$defs"][name]
    except KeyError as error:
        raise ValidationError(f"missing $defs entry for {ref}") from error

    if not isinstance(target, dict):
        raise ValidationError(f"$defs entry is not an object: {ref}")
    return target


def type_matches(value: Any, expected: str) -> bool:
    checks = {
        "object": lambda item: isinstance(item, dict),
        "array": lambda item: isinstance(item, list),
        "string": lambda item: isinstance(item, str),
        "integer": lambda item: isinstance(item, int) and not isinstance(item, bool),
        "number": lambda item: isinstance(item, (int, float)) and not isinstance(item, bool),
        "boolean": lambda item: isinstance(item, bool),
    }
    if expected not in checks:
        raise ValidationError(f"unsupported type: {expected}")
    return checks[expected](value)


def validate_value(value: Any, node: dict, root_schema: dict, path: str) -> None:
    if "$ref" in node:
        validate_value(value, resolve_ref(root_schema, node["$ref"]), root_schema, path)
        return

    expected_type = node.get("type")
    if expected_type and not type_matches(value, expected_type):
        raise ValidationError(f"{path}: expected {expected_type}, got {type(value).__name__}")

    if "const" in node and value != node["const"]:
        raise ValidationError(f"{path}: expected const {node['const']!r}")

    if "enum" in node and value not in node["enum"]:
        raise ValidationError(f"{path}: value {value!r} is not in enum")

    if isinstance(value, str):
        validate_string(value, node, path)
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        validate_number(value, node, path)
    elif isinstance(value, list):
        validate_array(value, node, root_schema, path)
    elif isinstance(value, dict):
        validate_object(value, node, root_schema, path)


def validate_string(value: str, node: dict, path: str) -> None:
    if "minLength" in node and len(value) < node["minLength"]:
        raise ValidationError(f"{path}: string is shorter than minLength {node['minLength']}")

    if "pattern" in node and not re.search(node["pattern"], value):
        raise ValidationError(f"{path}: string does not match pattern {node['pattern']!r}")


def validate_number(value: int | float, node: dict, path: str) -> None:
    if "minimum" in node and value < node["minimum"]:
        raise ValidationError(f"{path}: number is lower than minimum {node['minimum']}")

    if "maximum" in node and value > node["maximum"]:
        raise ValidationError(f"{path}: number is greater than maximum {node['maximum']}")


def validate_array(value: list, node: dict, root_schema: dict, path: str) -> None:
    if "minItems" in node and len(value) < node["minItems"]:
        raise ValidationError(f"{path}: array has fewer than minItems {node['minItems']}")

    if node.get("uniqueItems") and len({json.dumps(item, sort_keys=True) for item in value}) != len(value):
        raise ValidationError(f"{path}: array items are not unique")

    item_schema = node.get("items")
    if isinstance(item_schema, dict):
        for index, item in enumerate(value):
            validate_value(item, item_schema, root_schema, f"{path}[{index}]")


def validate_object(value: dict, node: dict, root_schema: dict, path: str) -> None:
    required = node.get("required", [])
    for key in required:
        if key not in value:
            raise ValidationError(f"{path}: missing required property {key!r}")

    properties = node.get("properties", {})
    additional = node.get("additionalProperties", True)

    for key, item in value.items():
        child_path = f"{path}.{key}"
        if key in properties:
            validate_value(item, properties[key], root_schema, child_path)
        elif isinstance(additional, dict):
            validate_value(item, additional, root_schema, child_path)
        elif additional is False:
            raise ValidationError(f"{path}: unexpected property {key!r}")


def validate_pair(schema_path: Path) -> None:
    example_path = schema_path.with_name(schema_path.name.replace(".schema.json", ".example.json"))
    schema = load_json(schema_path)
    example = load_json(example_path)
    validate_value(example, schema, schema, "$")


def main() -> int:
    failures = []
    for schema_path in sorted(SCHEMAS.glob("*.schema.json")):
        try:
            validate_pair(schema_path)
        except Exception as error:  # noqa: BLE001
            failures.append(f"{schema_path.name}: {error}")

    if failures:
        for failure in failures:
            print(f"invalid: {failure}", file=sys.stderr)
        return 1

    print("ok: schema examples validate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
