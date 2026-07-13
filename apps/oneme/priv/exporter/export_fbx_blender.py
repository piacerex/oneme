#!/usr/bin/env python3
"""Export an oneme GLB to FBX from a headless Blender process."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.armatures,
    ):
        for datablock in collection:
            if datablock.users == 0:
                collection.remove(datablock)


def export_fbx(source: Path, output: Path) -> None:
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(source))

    imported = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type in {"MESH", "ARMATURE", "EMPTY"}
    ]
    if not imported:
        raise RuntimeError("The GLB did not contain an exportable scene.")

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in imported:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = next(
        (obj for obj in imported if obj.type == "ARMATURE"), imported[0]
    )
    bpy.ops.export_scene.fbx(
        filepath=str(output),
        use_selection=True,
        object_types={"MESH", "ARMATURE", "EMPTY"},
        path_mode="COPY",
        embed_textures=True,
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
    )


def main() -> int:
    args = parse_args()
    export_fbx(Path(args.input), Path(args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
