# VRM Support

Phase 7 introduces a VRM-compatible export contract.

## MVP Scope

The current MVP does not create a rigged humanoid mesh. It creates a VRM-shaped
metadata contract and a GLB container that stores:

- avatar config
- humanoid bone map
- expression presets
- spring bone targets
- VRM meta and license fields

This allows the pipeline, API response, and validation flow to stabilize before
real rigged assets exist.

See `docs/vrm-validation.md` for viewer checks and animation compatibility
criteria.

## Humanoid Bones

Minimum bone map:

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

## Expression Presets

- neutral
- happy
- blink
- surprised

## Spring Bone Targets

- hair
- accessory

## Metadata Policy

- Author: oneme
- Contact: project repository
- License: match repository license until production assets override it
- Commercial use: allowed for project-owned placeholder assets

## Production Requirements

1. Replace procedural/placeholder geometry with humanoid rigged assets.
2. Validate humanoid bone mapping in a VRM viewer.
3. Convert expression presets into VRM expressions.
4. Convert spring targets into VRM spring bones.
5. Export `.vrm` as a true VRM 1.0 payload.
