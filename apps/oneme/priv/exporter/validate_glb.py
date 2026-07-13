#!/usr/bin/env python3
"""Validate the minimal GLB contract emitted by the oneme exporter."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A
GLB_BIN = 0x004E4942
UNSIGNED_BYTE = 5121
UNSIGNED_SHORT = 5123
UNSIGNED_INT = 5125

REQUIRED_HUMANOID_BONES = (
    "hips",
    "spine",
    "head",
    "leftUpperArm",
    "leftLowerArm",
    "leftHand",
    "rightUpperArm",
    "rightLowerArm",
    "rightHand",
    "leftUpperLeg",
    "leftLowerLeg",
    "leftFoot",
    "rightUpperLeg",
    "rightLowerLeg",
    "rightFoot",
)


def read_gltf(path: Path) -> tuple[dict, list[int], bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("file is too small to be a GLB")

    magic, version, total_length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("invalid GLB magic")
    if version != 2:
        raise ValueError(f"unsupported GLB version: {version}")
    if total_length != len(data):
        raise ValueError("declared GLB length does not match file length")

    offset = 12
    gltf = None
    binary = None
    chunk_types = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        start = offset + 8
        end = start + chunk_length
        if end > len(data):
            raise ValueError("GLB chunk extends past file end")
        body = data[start:end]
        chunk_types.append(chunk_type)
        if chunk_type == GLB_JSON:
            if gltf is not None:
                raise ValueError("GLB contains multiple JSON chunks")
            gltf = json.loads(body.decode("utf-8").rstrip(" "))
        elif chunk_type == GLB_BIN:
            binary = body
        offset = end

    if gltf is None:
        raise ValueError("GLB JSON chunk is missing")
    if GLB_BIN not in chunk_types:
        raise ValueError("GLB binary chunk is missing")
    if binary is None:
        raise ValueError("GLB binary chunk is missing")
    return gltf, chunk_types, binary


def validate_joint_attributes(gltf: dict, binary: bytes, skin: dict, mesh_indexes: list[int]) -> None:
    joint_count = len(skin["joints"])
    component_formats = {
        UNSIGNED_BYTE: ("<4B", 4),
        UNSIGNED_SHORT: ("<4H", 8),
        UNSIGNED_INT: ("<4I", 16),
    }

    for mesh_index in mesh_indexes:
        mesh = gltf["meshes"][mesh_index]
        for primitive in mesh.get("primitives", []):
            accessor_index = primitive.get("attributes", {}).get("JOINTS_0")
            if not isinstance(accessor_index, int):
                raise ValueError("every skinned primitive must contain JOINTS_0")
            accessor = gltf.get("accessors", [])[accessor_index]
            if accessor.get("type") != "VEC4" or accessor.get("componentType") not in component_formats:
                raise ValueError("JOINTS_0 must be an unsigned VEC4 accessor")
            buffer_view = gltf.get("bufferViews", [])[accessor["bufferView"]]
            format_string, element_size = component_formats[accessor["componentType"]]
            stride = buffer_view.get("byteStride", element_size)
            start = buffer_view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            end = start + max(accessor.get("count", 0) - 1, 0) * stride + element_size
            if start < 0 or end > len(binary):
                raise ValueError("JOINTS_0 accessor exceeds the GLB binary chunk")
            for index in range(accessor["count"]):
                values = struct.unpack_from(format_string, binary, start + index * stride)
                if any(value >= joint_count for value in values):
                    raise ValueError("JOINTS_0 references a skin joint outside skin.joints")


def validate_vrm(gltf: dict) -> None:
    extensions = gltf.get("extensions", {})
    vrm = extensions.get("VRMC_vrm")
    spring_bone = extensions.get("VRMC_springBone")
    if not isinstance(vrm, dict) or vrm.get("specVersion") != "1.0":
        raise ValueError("VRMC_vrm 1.0 extension is missing")
    if not isinstance(spring_bone, dict) or spring_bone.get("specVersion") != "1.0":
        raise ValueError("VRMC_springBone 1.0 extension is missing")

    meta = vrm.get("meta")
    if not isinstance(meta, dict) or not meta.get("name") or not meta.get("authors") or not meta.get("licenseUrl"):
        raise ValueError("VRM meta requires name, authors, and licenseUrl")

    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    skins = gltf.get("skins", [])
    humanoid = vrm.get("humanoid", {}).get("humanBones")
    if not isinstance(humanoid, dict):
        raise ValueError("VRM humanoid.humanBones is missing")
    if any(bone not in humanoid for bone in REQUIRED_HUMANOID_BONES):
        raise ValueError("VRM humanoid is missing a required bone")

    human_node_indexes = []
    for bone, entry in humanoid.items():
        if not isinstance(entry, dict) or not isinstance(entry.get("node"), int):
            raise ValueError(f"VRM humanoid bone {bone} has no node reference")
        node_index = entry["node"]
        if node_index < 0 or node_index >= len(nodes):
            raise ValueError(f"VRM humanoid bone {bone} references an invalid node")
        human_node_indexes.append(node_index)
    if len(human_node_indexes) != len(set(human_node_indexes)):
        raise ValueError("VRM humanoid bone nodes must be unique")

    mesh_node_indexes = [index for index, node in enumerate(nodes) if isinstance(node.get("mesh"), int)]
    if not mesh_node_indexes or not skins:
        raise ValueError("VRM requires a skinned mesh and skin")
    for node_index in mesh_node_indexes:
        node = nodes[node_index]
        if not isinstance(node.get("skin"), int) or node["skin"] >= len(skins):
            raise ValueError("every mesh node must reference a valid skin")
    skin_index = nodes[mesh_node_indexes[0]]["skin"]
    if skin_index < 0:
        raise ValueError("VRM mesh node has an invalid skin index")
    skin = skins[skin_index]
    if not isinstance(skin.get("joints"), list) or len(skin["joints"]) < len(REQUIRED_HUMANOID_BONES):
        raise ValueError("VRM skin has too few joints")
    if any(not isinstance(node, int) or node < 0 or node >= len(nodes) for node in skin["joints"]):
        raise ValueError("VRM skin contains an invalid joint node")

    expressions = vrm.get("expressions", {}).get("preset")
    if not isinstance(expressions, dict) or not {"neutral", "happy", "blink", "surprised"}.issubset(expressions):
        raise ValueError("VRM expressions preset is incomplete")
    for expression_name, expression in expressions.items():
        if not isinstance(expression, dict):
            raise ValueError(f"VRM expression {expression_name} is invalid")
        for bind in expression.get("morphTargetBinds", []):
            node_index = bind.get("node")
            target_index = bind.get("index")
            if not isinstance(node_index, int) or not isinstance(target_index, int):
                raise ValueError(f"VRM expression {expression_name} has an invalid morph bind")
            if node_index < 0 or node_index >= len(nodes) or not isinstance(nodes[node_index].get("mesh"), int):
                raise ValueError(f"VRM expression {expression_name} targets a non-mesh node")
            mesh = meshes[nodes[node_index]["mesh"]]
            target_names = mesh.get("extras", {}).get("targetNames", [])
            if target_index < 0 or target_index >= len(target_names):
                raise ValueError(f"VRM expression {expression_name} targets an invalid morph")

    if not isinstance(spring_bone.get("springs"), list) or not spring_bone["springs"]:
        raise ValueError("VRM spring bone chain is missing")
    for spring in spring_bone["springs"]:
        joints = spring.get("joints", [])
        if not isinstance(joints, list) or len(joints) < 2:
            raise ValueError("VRM spring bone chain needs two joints")
        for joint in joints:
            if not isinstance(joint, dict) or not isinstance(joint.get("node"), int):
                raise ValueError("VRM spring bone joint has no node reference")
            if joint["node"] < 0 or joint["node"] >= len(nodes):
                raise ValueError("VRM spring bone references an invalid node")


def validate(path: Path, require_vrm: bool) -> dict:
    gltf, chunk_types, binary = read_gltf(path)
    asset = gltf.get("asset", {})
    if asset.get("version") != "2.0":
        raise ValueError("gltf asset version is not 2.0")
    meshes = gltf.get("meshes", [])
    if not isinstance(meshes, list) or not meshes:
        raise ValueError("GLB must contain at least one mesh")

    if require_vrm:
        vrm = gltf.get("extensions", {}).get("VRMC_vrm")
        extras_vrm = asset.get("extras", {}).get("vrm")
        if "VRMC_vrm" not in gltf.get("extensionsUsed", []):
            raise ValueError("VRMC_vrm is not listed in extensionsUsed")
        if not isinstance(vrm, dict) or not isinstance(extras_vrm, dict):
            raise ValueError("VRM metadata is missing")
        validate_vrm(gltf)
        mesh_node_indexes = [index for index, node in enumerate(gltf["nodes"]) if isinstance(node.get("mesh"), int)]
        skin_index = gltf["nodes"][mesh_node_indexes[0]]["skin"]
        validate_joint_attributes(
            gltf,
            binary,
            gltf["skins"][skin_index],
            [gltf["nodes"][index]["mesh"] for index in mesh_node_indexes],
        )

    return {
        "file": str(path),
        "bytes": path.stat().st_size,
        "meshCount": len(meshes),
        "chunkTypes": chunk_types,
        "vrm": require_vrm,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--require-vrm", action="store_true")
    args = parser.parse_args()

    try:
        result = validate(Path(args.input), args.require_vrm)
    except Exception as error:  # noqa: BLE001
        print(f"invalid: {error}")
        return 1

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
