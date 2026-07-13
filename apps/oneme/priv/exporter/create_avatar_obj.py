#!/usr/bin/env python3
"""Create a deterministic procedural avatar OBJ for the local export worker."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


PALETTES = {
    "top.basic_01": (0.204, 0.498, 0.482),
    "top.hoodie_01": (0.435, 0.310, 0.561),
    "top.jacket_01": (0.184, 0.247, 0.329),
    "bottom.basic_01": (0.212, 0.239, 0.286),
    "bottom.tapered_01": (0.373, 0.400, 0.373),
    "bottom.skirt_01": (0.482, 0.298, 0.345),
}


class ObjBuilder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.faces: list[tuple[str, list[tuple[int, int]]]] = []

    def vertex(self, point: tuple[float, float, float]) -> int:
        self.vertices.append(point)
        return len(self.vertices)

    def uv(self, point: tuple[float, float]) -> int:
        self.uvs.append(point)
        return len(self.uvs)

    def face(self, material: str, points: list[tuple[int, int]]) -> None:
        self.faces.append((material, points))

    def add_box(
        self,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: str,
    ) -> None:
        cx, cy, cz = center
        sx, sy, sz = (value / 2 for value in size)
        corners = [
            (cx - sx, cy - sy, cz - sz),
            (cx + sx, cy - sy, cz - sz),
            (cx + sx, cy + sy, cz - sz),
            (cx - sx, cy + sy, cz - sz),
            (cx - sx, cy - sy, cz + sz),
            (cx + sx, cy - sy, cz + sz),
            (cx + sx, cy + sy, cz + sz),
            (cx - sx, cy + sy, cz + sz),
        ]
        indices = [self.vertex(corner) for corner in corners]
        uv = [self.uv((0, 0)), self.uv((1, 0)), self.uv((1, 1)), self.uv((0, 1))]
        for side in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7)):
            self.face(material, [(indices[index], uv[position]) for position, index in enumerate(side)])

    def add_sphere(
        self,
        center: tuple[float, float, float],
        radius: tuple[float, float, float],
        material: str,
        segments: int = 20,
        rings: int = 12,
        theta_start: float = 0.0,
        theta_length: float = math.pi * 2,
    ) -> None:
        cx, cy, cz = center
        rx, ry, rz = radius
        partial = abs(abs(theta_length) - math.pi * 2) > 0.0001
        segment_count = segments + 1 if partial else segments
        points: list[list[tuple[int, int]]] = []
        for ring in range(rings + 1):
            v = ring / rings
            phi = math.pi * v
            row = []
            for segment in range(segment_count):
                u = segment / (segment_count - 1) if partial else segment / segments
                theta = theta_start + theta_length * u
                point = (cx + rx * math.sin(phi) * math.cos(theta), cy + ry * math.cos(phi), cz + rz * math.sin(phi) * math.sin(theta))
                row.append((self.vertex(point), self.uv((u, 1 - v))))
            points.append(row)

        for ring in range(rings):
            segment_limit = segment_count - 1 if partial else segments
            for segment in range(segment_limit):
                next_segment = segment + 1 if partial else (segment + 1) % segments
                self.face(material, [points[ring][segment], points[ring][next_segment], points[ring + 1][next_segment], points[ring + 1][segment]])

    def add_head(
        self,
        center: tuple[float, float, float],
        radius: tuple[float, float, float],
        material: str,
        shape: dict[str, float],
        segments: int = 64,
        rings: int = 32,
        theta_start: float = 0.0,
        theta_length: float = math.pi * 2,
        inflation: float = 1.0,
    ) -> None:
        cx, cy, cz = center
        rx, ry, rz = radius
        partial = abs(abs(theta_length) - math.pi * 2) > 0.0001
        segment_count = segments + 1 if partial else segments
        points: list[list[tuple[int, int]]] = []

        for ring in range(rings + 1):
            v = ring / rings
            vertical = math.cos(v * math.pi)
            ring_radius = math.sin(v * math.pi)
            if vertical >= 0:
                contour = lerp(1.0, shape["forehead_width"], vertical)
            else:
                contour = lerp(shape["jaw_width"], 1.0, vertical + 1.0)

            egg_taper = 0.9 + 0.1 * ((vertical + 1.0) / 2.0)
            x_radius = rx * shape["width_scale"] * ring_radius * contour * egg_taper * inflation
            y_radius = ry * shape["height_scale"] * inflation
            z_radius = rz * shape["depth_scale"] * ring_radius * (0.94 + contour * 0.06) * inflation
            row: list[tuple[int, int]] = []

            for segment in range(segment_count):
                u = segment / (segment_count - 1) if partial else segment / segments
                theta = theta_start + theta_length * u
                point = (
                    cx + x_radius * math.cos(theta),
                    cy + y_radius * vertical,
                    cz + z_radius * math.sin(theta),
                )
                row.append((self.vertex(point), self.uv((u, 1 - v))))

            points.append(row)

        for ring in range(rings):
            segment_limit = segment_count - 1 if partial else segments
            for segment in range(segment_limit):
                next_segment = segment + 1 if partial else (segment + 1) % segments
                self.face(
                    material,
                    [
                        points[ring][segment],
                        points[ring][next_segment],
                        points[ring + 1][next_segment],
                        points[ring + 1][segment],
                    ],
                )

    def write(self, output: Path, materials: dict[str, tuple[float, float, float]], textures: dict[str, Path]) -> None:
        mtl_path = output.with_suffix(".mtl")
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("w", encoding="utf-8") as obj:
            obj.write(f"mtllib {mtl_path.name}\n")
            obj.write("o OnemeAvatar\n")
            for x, y, z in self.vertices:
                obj.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for u, v in self.uvs:
                obj.write(f"vt {u:.6f} {v:.6f}\n")
            current_material = None
            for material, points in self.faces:
                if material != current_material:
                    obj.write(f"usemtl {material}\n")
                    current_material = material
                obj.write("f " + " ".join(f"{vertex}/{uv}" for vertex, uv in points) + "\n")

        with mtl_path.open("w", encoding="utf-8") as mtl:
            for name, color in materials.items():
                mtl.write(f"newmtl {name}\nKd {color[0]:.5f} {color[1]:.5f} {color[2]:.5f}\nKa 0 0 0\nKs 0.1 0.1 0.1\nNs 24\n\n")
            for name, texture in textures.items():
                mtl.write(f"newmtl {name}\nKd 1 1 1\nmap_Kd {texture.name}\n\n")


def hex_color(value: str, fallback: tuple[float, float, float]) -> tuple[float, float, float]:
    try:
        raw = value.lstrip("#")
        return tuple(int(raw[index : index + 2], 16) / 255 for index in (0, 2, 4))  # type: ignore[return-value]
    except (TypeError, ValueError):
        return fallback


def lerp(start: float, end: float, amount: float) -> float:
    return start + (end - start) * amount


def clamp(value: float, minimum: float, maximum: float) -> float:
    return min(maximum, max(minimum, value))


def numeric(value: object, fallback: float) -> float:
    try:
        parsed = float(value)  # type: ignore[arg-type]
        return parsed if math.isfinite(parsed) else fallback
    except (TypeError, ValueError):
        return fallback


def horizontal_span(mapped: dict, left_key: str, right_key: str) -> float | None:
    left = mapped.get(left_key)
    right = mapped.get(right_key)
    if not isinstance(left, dict) or not isinstance(right, dict):
        return None
    if not isinstance(left.get("x"), (int, float)) or not isinstance(right.get("x"), (int, float)):
        return None
    return abs(float(right["x"]) - float(left["x"]))


def head_shape(config: dict) -> dict[str, float]:
    morph = config.get("faceMorph", {})
    morph = morph if isinstance(morph, dict) else {}
    analysis = config.get("faceAnalysis", {})
    analysis = analysis if isinstance(analysis, dict) else {}
    calibration = analysis.get("calibration", {})
    calibration = calibration if isinstance(calibration, dict) else {}
    mapped = calibration.get("mappedLandmarks", {})
    mapped = mapped if isinstance(mapped, dict) else {}

    cheek_span = horizontal_span(mapped, "leftCheek", "rightCheek")
    jaw_span = horizontal_span(mapped, "leftJaw", "rightJaw")
    temple_span = horizontal_span(mapped, "leftTemple", "rightTemple")

    return {
        "width_scale": clamp(numeric(morph.get("widthScale"), 1.0), 0.82, 1.2),
        "height_scale": clamp(numeric(morph.get("heightScale"), 1.06), 0.9, 1.24),
        "depth_scale": clamp(0.82 + numeric(morph.get("depth"), 0.5) * 0.18, 0.78, 1.04),
        "forehead_width": clamp(temple_span / cheek_span, 0.78, 1.04)
        if temple_span and cheek_span
        else 0.9,
        "jaw_width": clamp(jaw_span / cheek_span, 0.52, 0.98)
        if jaw_span and cheek_span
        else 0.76,
    }


def build(config: dict, output: Path, face_texture: Path | None, profile_texture: Path | None) -> None:
    parts = config.get("parts", {})
    colors = config.get("colors", {})
    builder = ObjBuilder()
    skin = hex_color(colors.get("skin", "#c98f6f"), (0.79, 0.56, 0.44))
    top = PALETTES.get(parts.get("top"), (0.204, 0.498, 0.482))
    bottom = PALETTES.get(parts.get("bottom"), (0.212, 0.239, 0.286))
    materials = {"skin": skin, "top": top, "bottom": bottom, "shoes": (0.14, 0.14, 0.14)}
    textures: dict[str, Path] = {}
    shape = head_shape(config)

    builder.add_box((0, 0.35, 0), (1.35, 1.35, 0.82), "top")
    builder.add_box((0, 1.23, 0), (0.32, 0.28, 0.32), "skin")
    builder.add_head((0, 1.78, 0), (0.48, 0.51, 0.43), "skin", shape)
    if face_texture:
        materials["face_texture"] = (1.0, 1.0, 1.0)
        textures["face_texture"] = face_texture
        builder.add_head(
            (0, 1.78, 0),
            (0.48, 0.51, 0.43),
            "face_texture",
            shape,
            theta_start=math.pi,
            theta_length=-math.pi,
            inflation=1.018,
        )
    if profile_texture:
        materials["profile_texture"] = (1.0, 1.0, 1.0)
        textures["profile_texture"] = profile_texture
        builder.add_head(
            (0, 1.78, 0),
            (0.48, 0.51, 0.43),
            "profile_texture",
            shape,
            theta_start=0,
            theta_length=-math.pi,
            inflation=1.016,
        )
    builder.add_box((-0.78, 0.36, 0), (0.28, 0.9, 0.45), "top")
    builder.add_box((0.78, 0.36, 0), (0.28, 0.9, 0.45), "top")
    builder.add_sphere((-0.88, -0.3, 0), (0.18, 0.2, 0.18), "skin")
    builder.add_sphere((0.88, -0.3, 0), (0.18, 0.2, 0.18), "skin")
    builder.add_box((-0.22, -1.02, 0), (0.28, 1.0, 0.36), "bottom")
    builder.add_box((0.22, -1.02, 0), (0.28, 1.0, 0.36), "bottom")
    builder.add_box((-0.22, -1.56, 0.08), (0.5, 0.22, 0.72), "shoes")
    builder.add_box((0.22, -1.56, 0.08), (0.5, 0.22, 0.72), "shoes")

    builder.write(output, materials, textures)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--face-texture")
    parser.add_argument("--profile-texture")
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    build(
        config,
        Path(args.out),
        Path(args.face_texture) if args.face_texture else None,
        Path(args.profile_texture) if args.profile_texture else None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
