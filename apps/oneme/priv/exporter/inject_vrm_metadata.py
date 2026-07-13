#!/usr/bin/env python3
"""Convert an exported GLB into a small, deterministic VRM 1.0 rig."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path


GLB_MAGIC = 0x46546C67
GLB_JSON = 0x4E4F534A
GLB_BIN = 0x004E4942
ARRAY_BUFFER = 34962
FLOAT = 5126
UNSIGNED_SHORT = 5123

HUMANOID_BONES = (
    "hips",
    "spine",
    "chest",
    "neck",
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

SKIN_JOINTS = HUMANOID_BONES + ("OnemeHairRoot", "OnemeHairTip")
MORPH_TARGETS = ("happy", "blink", "surprised", "neutral")


def pad_json(value: bytes) -> bytes:
    return value + (b" " * ((-len(value)) % 4))


def read_chunks(data: bytes) -> tuple[dict, list[tuple[int, bytes]]]:
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
    chunks: list[tuple[int, bytes]] = []
    gltf: dict | None = None
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        start = offset + 8
        end = start + chunk_length
        if end > len(data):
            raise ValueError("GLB chunk extends past file end")
        chunk = data[start:end]
        if chunk_type == GLB_JSON:
            if gltf is not None:
                raise ValueError("GLB contains multiple JSON chunks")
            gltf = json.loads(chunk.decode("utf-8").rstrip(" "))
        else:
            chunks.append((chunk_type, chunk))
        offset = end

    if gltf is None:
        raise ValueError("GLB JSON chunk is missing")
    if not any(chunk_type == GLB_BIN for chunk_type, _ in chunks):
        raise ValueError("GLB binary chunk is missing")
    return gltf, chunks


def write_glb(gltf: dict, chunks: list[tuple[int, bytes]], output: Path) -> None:
    json_chunk = pad_json(json.dumps(gltf, separators=(",", ":"), ensure_ascii=True).encode("utf-8"))
    encoded_chunks = [struct.pack("<II", len(json_chunk), GLB_JSON) + json_chunk]
    encoded_chunks.extend(struct.pack("<II", len(chunk), chunk_type) + chunk for chunk_type, chunk in chunks)
    body = b"".join(encoded_chunks)
    header = struct.pack("<III", GLB_MAGIC, 2, 12 + len(body))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + body)


def binary_chunk(chunks: list[tuple[int, bytes]]) -> tuple[int, bytearray]:
    for index, (chunk_type, chunk) in enumerate(chunks):
        if chunk_type == GLB_BIN:
            return index, bytearray(chunk)
    raise ValueError("GLB binary chunk is missing")


def append_binary(
    gltf: dict,
    chunks: list[tuple[int, bytes]],
    blob: bytearray,
    payload: bytes,
    target: int | None = ARRAY_BUFFER,
) -> int:
    while len(blob) % 4:
        blob.append(0)
    offset = len(blob)
    blob.extend(payload)
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(payload)}
    if target is not None:
        view["target"] = target
    gltf.setdefault("bufferViews", []).append(view)
    gltf.setdefault("buffers", [{}])[0]["byteLength"] = len(blob)
    return len(gltf["bufferViews"]) - 1


def append_accessor(
    gltf: dict,
    chunks: list[tuple[int, bytes]],
    blob: bytearray,
    payload: bytes,
    count: int,
    component_type: int,
    value_type: str,
    target: int | None = ARRAY_BUFFER,
    minimum: list[float] | None = None,
    maximum: list[float] | None = None,
) -> int:
    view_index = append_binary(gltf, chunks, blob, payload, target)
    accessor = {
        "bufferView": view_index,
        "byteOffset": 0,
        "componentType": component_type,
        "count": count,
        "type": value_type,
    }
    if minimum is not None:
        accessor["min"] = minimum
    if maximum is not None:
        accessor["max"] = maximum
    gltf.setdefault("accessors", []).append(accessor)
    return len(gltf["accessors"]) - 1


def accessor_positions(gltf: dict, blob: bytes, accessor_index: int) -> list[tuple[float, float, float]]:
    accessor = gltf["accessors"][accessor_index]
    if accessor.get("componentType") != FLOAT or accessor.get("type") != "VEC3":
        raise ValueError("POSITION accessor must be a float VEC3")

    view = gltf["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", 12)
    positions = []
    for index in range(accessor["count"]):
        position = struct.unpack_from("<3f", blob, start + index * stride)
        positions.append(position)
    return positions


def material_name(gltf: dict, primitive: dict) -> str:
    material_index = primitive.get("material")
    materials = gltf.get("materials", [])
    if isinstance(material_index, int) and material_index < len(materials):
        return str(materials[material_index].get("name", ""))
    return ""


def choose_joint(position: tuple[float, float, float], material: str, joint_indexes: dict[str, int]) -> int:
    x, y, _z = position
    if material == "hair":
        return joint_indexes["OnemeHairTip" if y > 1.85 else "OnemeHairRoot"]
    if y >= 1.4:
        return joint_indexes["head"]
    if y >= 1.05:
        return joint_indexes["neck"]
    if abs(x) > 0.55:
        side = "left" if x < 0 else "right"
        if y >= 0.25:
            return joint_indexes[f"{side}UpperArm"]
        if y >= -0.12:
            return joint_indexes[f"{side}LowerArm"]
        return joint_indexes[f"{side}Hand"]
    if y < -1.4:
        return joint_indexes["leftFoot" if x < 0 else "rightFoot"]
    if y < -0.5:
        return joint_indexes["leftLowerLeg" if x < 0 else "rightLowerLeg"]
    if y < -0.12:
        return joint_indexes["leftUpperLeg" if x < 0 else "rightUpperLeg"]
    if y < 0.35:
        return joint_indexes["hips"]
    if y < 0.75:
        return joint_indexes["spine"]
    return joint_indexes["chest"]


def morph_delta(
    target: str, position: tuple[float, float, float], material: str
) -> tuple[float, float, float]:
    x, y, _z = position
    face_like = material in {"skin", "face_texture"}
    if not face_like or y < 1.38:
        return (0.0, 0.0, 0.0)

    if target == "happy" and 1.43 <= y <= 1.82:
        width = max(0.0, 1.0 - abs(x) / 0.52)
        height = max(0.0, 1.0 - abs(y - 1.62) / 0.2)
        return (0.0, 0.0, 0.035 * width * height)
    if target == "blink" and 1.72 <= y <= 2.02:
        width = max(0.0, 1.0 - abs(x) / 0.46)
        return (0.0, -0.018 * width, 0.0)
    if target == "surprised" and 1.43 <= y <= 1.72:
        width = max(0.0, 1.0 - abs(x) / 0.5)
        return (0.0, 0.0, 0.028 * width)
    return (0.0, 0.0, 0.0)


def translation_matrix(position: tuple[float, float, float]) -> list[float]:
    x, y, z = position
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -x, -y, -z, 1.0]


def make_nodes(gltf: dict) -> tuple[dict[str, int], int, int]:
    nodes = gltf.setdefault("nodes", [])
    if not nodes:
        raise ValueError("VRM export requires at least one glTF node")

    scene_index = gltf.get("scene", 0)
    scene_roots = gltf.setdefault("scenes", [{"nodes": [0]}])[scene_index].setdefault("nodes", [])
    root_index = scene_roots[0] if scene_roots else 0
    if not scene_roots:
        scene_roots.append(root_index)

    positions = {
        "hips": (0.0, -0.35, 0.0),
        "spine": (0.0, 0.15, 0.0),
        "chest": (0.0, 0.70, 0.0),
        "neck": (0.0, 1.25, 0.0),
        "head": (0.0, 1.72, 0.0),
        "leftUpperArm": (-0.75, 0.65, 0.0),
        "leftLowerArm": (-0.82, 0.10, 0.0),
        "leftHand": (-0.88, -0.30, 0.0),
        "rightUpperArm": (0.75, 0.65, 0.0),
        "rightLowerArm": (0.82, 0.10, 0.0),
        "rightHand": (0.88, -0.30, 0.0),
        "leftUpperLeg": (-0.22, -0.55, 0.0),
        "leftLowerLeg": (-0.22, -1.08, 0.0),
        "leftFoot": (-0.22, -1.56, 0.08),
        "rightUpperLeg": (0.22, -0.55, 0.0),
        "rightLowerLeg": (0.22, -1.08, 0.0),
        "rightFoot": (0.22, -1.56, 0.08),
        "OnemeHairRoot": (0.0, 1.98, -0.02),
        "OnemeHairTip": (0.0, 2.32, -0.02),
    }
    parents = {
        "hips": None,
        "spine": "hips",
        "chest": "spine",
        "neck": "chest",
        "head": "neck",
        "leftUpperArm": "chest",
        "leftLowerArm": "leftUpperArm",
        "leftHand": "leftLowerArm",
        "rightUpperArm": "chest",
        "rightLowerArm": "rightUpperArm",
        "rightHand": "rightLowerArm",
        "leftUpperLeg": "hips",
        "leftLowerLeg": "leftUpperLeg",
        "leftFoot": "leftLowerLeg",
        "rightUpperLeg": "hips",
        "rightLowerLeg": "rightUpperLeg",
        "rightFoot": "rightLowerLeg",
        "OnemeHairRoot": "head",
        "OnemeHairTip": "OnemeHairRoot",
    }

    indexes: dict[str, int] = {}
    for name in SKIN_JOINTS:
        parent = parents[name]
        parent_position = positions[parent] if parent else (0.0, 0.0, 0.0)
        world_position = positions[name]
        local_position = tuple(world - parent_value for world, parent_value in zip(world_position, parent_position))
        index = len(nodes)
        indexes[name] = index
        nodes.append({"name": name, "translation": list(local_position)})
        if parent:
            nodes[indexes[parent]].setdefault("children", []).append(index)
        else:
            nodes[root_index].setdefault("children", []).append(index)

    return indexes, root_index, indexes["hips"]


def add_skin(gltf: dict, chunks: list[tuple[int, bytes]], blob: bytearray, joint_indexes: dict[str, int]) -> int:
    joint_world_positions = {
        "hips": (0.0, -0.35, 0.0),
        "spine": (0.0, 0.15, 0.0),
        "chest": (0.0, 0.70, 0.0),
        "neck": (0.0, 1.25, 0.0),
        "head": (0.0, 1.72, 0.0),
        "leftUpperArm": (-0.75, 0.65, 0.0),
        "leftLowerArm": (-0.82, 0.10, 0.0),
        "leftHand": (-0.88, -0.30, 0.0),
        "rightUpperArm": (0.75, 0.65, 0.0),
        "rightLowerArm": (0.82, 0.10, 0.0),
        "rightHand": (0.88, -0.30, 0.0),
        "leftUpperLeg": (-0.22, -0.55, 0.0),
        "leftLowerLeg": (-0.22, -1.08, 0.0),
        "leftFoot": (-0.22, -1.56, 0.08),
        "rightUpperLeg": (0.22, -0.55, 0.0),
        "rightLowerLeg": (0.22, -1.08, 0.0),
        "rightFoot": (0.22, -1.56, 0.08),
        "OnemeHairRoot": (0.0, 1.98, -0.02),
        "OnemeHairTip": (0.0, 2.32, -0.02),
    }
    inverse_bindings = b"".join(struct.pack("<16f", *translation_matrix(joint_world_positions[name])) for name in SKIN_JOINTS)
    inverse_bind_accessor = append_accessor(
        gltf, chunks, blob, inverse_bindings, len(SKIN_JOINTS), FLOAT, "MAT4", target=None
    )

    mesh_nodes = [index for index, node in enumerate(gltf.get("nodes", [])) if isinstance(node.get("mesh"), int)]
    if not mesh_nodes:
        raise ValueError("VRM export requires a node with a mesh")
    skin_index = len(gltf.setdefault("skins", []))
    gltf["skins"].append(
        {
            "inverseBindMatrices": inverse_bind_accessor,
            "joints": [joint_indexes[name] for name in SKIN_JOINTS],
            "skeleton": joint_indexes["hips"],
            "name": "OnemeHumanoidSkin",
        }
    )
    for node_index in mesh_nodes:
        gltf["nodes"][node_index]["skin"] = skin_index
    return mesh_nodes[0]


def add_vertex_attributes(
    gltf: dict,
    chunks: list[tuple[int, bytes]],
    blob: bytearray,
    mesh_node_index: int,
    joint_indexes: dict[str, int],
) -> None:
    mesh = gltf["meshes"][gltf["nodes"][mesh_node_index]["mesh"]]
    mesh.setdefault("extras", {})["targetNames"] = list(MORPH_TARGETS)
    for primitive in mesh.get("primitives", []):
        positions = accessor_positions(gltf, bytes(blob), primitive["attributes"]["POSITION"])
        material = material_name(gltf, primitive)
        joints = [choose_joint(position, material, joint_indexes) for position in positions]
        joints_payload = b"".join(struct.pack("<4H", joint, 0, 0, 0) for joint in joints)
        weights_payload = b"".join(struct.pack("<4f", 1.0, 0.0, 0.0, 0.0) for _ in positions)
        primitive["attributes"]["JOINTS_0"] = append_accessor(
            gltf, chunks, blob, joints_payload, len(positions), UNSIGNED_SHORT, "VEC4"
        )
        primitive["attributes"]["WEIGHTS_0"] = append_accessor(
            gltf, chunks, blob, weights_payload, len(positions), FLOAT, "VEC4"
        )

        targets = []
        for target in MORPH_TARGETS:
            payload = b"".join(
                struct.pack("<3f", *morph_delta(target, position, material)) for position in positions
            )
            targets.append(
                {
                    "POSITION": append_accessor(
                        gltf, chunks, blob, payload, len(positions), FLOAT, "VEC3", minimum=[0.0, 0.0, 0.0], maximum=[0.0, 0.0, 0.0]
                    )
                }
            )
        primitive["targets"] = targets
    mesh["weights"] = [0.0] * len(MORPH_TARGETS)


def expression(target_index: int | None = None, node_index: int | None = None) -> dict:
    result = {
        "isBinary": False,
        "morphTargetBinds": [],
        "materialColorBinds": [],
        "textureTransformBinds": [],
    }
    if target_index is not None and node_index is not None:
        result["morphTargetBinds"].append({"node": node_index, "index": target_index, "weight": 1.0})
    return result


def vrm_extensions(
    config: dict,
    joint_indexes: dict[str, int],
    mesh_node_index: int,
) -> tuple[dict, dict]:
    name = config.get("name") or config.get("avatarName") or "oneme avatar"
    meta = {
        "name": str(name)[:80],
        "version": "0.1.0",
        "authors": ["oneme"],
        "contactInformation": "https://github.com/piacerex/oneme",
        "licenseUrl": "https://vrm.dev/licenses/1.0/",
        "avatarPermission": "everyone",
        "commercialUsage": "corporation",
        "allowRedistribution": True,
        "modification": "allowModificationRedistribution",
        "creditNotation": "required",
    }
    humanoid = {bone: {"node": joint_indexes[bone]} for bone in HUMANOID_BONES}
    expressions = {
        "preset": {
            "neutral": expression(),
            "happy": expression(0, mesh_node_index),
            "blink": expression(1, mesh_node_index),
            "surprised": expression(2, mesh_node_index),
        },
        "custom": {},
    }
    vrm = {
        "specVersion": "1.0",
        "meta": meta,
        "humanoid": {"humanBones": humanoid},
        "expressions": expressions,
    }
    spring_bone = {
        "specVersion": "1.0",
        "colliders": [
            {
                "node": joint_indexes["head"],
                "shape": {"sphere": {"offset": [0.0, 0.0, 0.0], "radius": 0.28}},
            }
        ],
        "colliderGroups": [{"name": "head", "colliders": [0]}],
        "springs": [
            {
                "name": "OnemeHairSpring",
                "joints": [
                    {
                        "node": joint_indexes["OnemeHairRoot"],
                        "hitRadius": 0.06,
                        "stiffness": 0.5,
                        "gravityPower": 0.15,
                        "gravityDir": [0.0, -1.0, 0.0],
                        "dragForce": 0.35,
                    },
                    {"node": joint_indexes["OnemeHairTip"]},
                ],
                "colliderGroups": [0],
                "center": joint_indexes["head"],
            }
        ],
    }
    return vrm, spring_bone


def inject(source: Path, output: Path, config: dict) -> None:
    gltf, chunks = read_chunks(source.read_bytes())
    bin_index, blob = binary_chunk(chunks)
    joint_indexes, _root_index, _hips_index = make_nodes(gltf)
    mesh_node_index = add_skin(gltf, chunks, blob, joint_indexes)
    add_vertex_attributes(gltf, chunks, blob, mesh_node_index, joint_indexes)
    vrm, spring_bone = vrm_extensions(config, joint_indexes, mesh_node_index)

    extensions_used = list(gltf.get("extensionsUsed", []))
    for extension in ("VRMC_vrm", "VRMC_springBone"):
        if extension not in extensions_used:
            extensions_used.append(extension)
    gltf["extensionsUsed"] = extensions_used
    gltf.setdefault("extensions", {})["VRMC_vrm"] = vrm
    gltf["extensions"]["VRMC_springBone"] = spring_bone
    asset = gltf.setdefault("asset", {})
    asset["generator"] = "oneme VRM 1.0 rig exporter"
    asset.setdefault("extras", {})["vrm"] = {
        "specVersion": "1.0",
        "humanoid": list(HUMANOID_BONES),
        "expressions": list(vrm["expressions"]["preset"]),
        "springBones": ["OnemeHairRoot", "OnemeHairTip"],
    }
    chunks[bin_index] = (GLB_BIN, bytes(blob))
    write_glb(gltf, chunks, output)


def main() -> int:
    parser = argparse.ArgumentParser(description="Add a VRM 1.0 humanoid rig to a GLB.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--config", required=True)
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    inject(Path(args.input), Path(args.output), config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
