# VRM Validation Plan

Phase 7 validates the VRM path in two layers.

## MVP Validation

The local MVP exports a `.vrm` file as a GLB container with VRM-shaped metadata.
Validate it with:

```bash
python3 tools/gltf/validate_vrm.py path/to/avatar.vrm
```

Expected result:

- GLB magic and version are valid
- glTF asset version is `2.0`
- `asset.extras.vrm` exists
- `extensions.VRMC_vrm` exists
- humanoid bone map has the Phase 7 minimum bones
- expression presets exist

## Viewer Check

Use a VRM-capable viewer after exporting a sample file.

1. Export `local-demo.vrm` from the web app.
2. Run `tools/gltf/validate_vrm.py local-demo.vrm`.
3. Open the file in a VRM viewer.
4. Confirm the viewer reports VRM metadata.
5. Confirm failures are recorded if the viewer requires a true rigged VRM 1.0 payload.

The current expected viewer result is partial compatibility: metadata can be
inspected, but humanoid animation will not run until real rigged assets replace
the placeholder scene.

## Animation Compatibility

The minimum animation target set is:

- hips
- spine
- chest
- neck
- head
- leftUpperArm
- leftLowerArm
- leftHand
- rightUpperArm
- rightLowerArm
- rightHand
- leftUpperLeg
- leftLowerLeg
- leftFoot
- rightUpperLeg
- rightLowerLeg
- rightFoot

The MVP is compatible at the contract level when all targets are present in the
VRM humanoid map. Runtime animation compatibility remains blocked on real rigged
geometry and skinning.
