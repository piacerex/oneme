# Three.js Preview

Phase 1 now includes a browser-side Three.js preview alongside the existing Canvas MVP.

## Purpose

- Prove the app can render a real 3D scene.
- Keep avatar configuration JSON as the source of truth.
- Prepare the path from Canvas placeholder avatar to `.glb` parts.

## MVP Scope

The initial Three.js preview uses procedural geometry:

- capsule-like body
- sphere head
- simple hair shell
- cylinders for limbs
- generated face texture color hints

It does not yet load production `.glb` assets. The procedural scene is a bridge
between the current Canvas MVP and the later GLB pipeline.

## Sync Contract

The viewer reads:

- `parts.face`
- `parts.hair`
- `parts.top`
- `parts.bottom`
- `parts.shoes`
- `colors.skin`
- `colors.hair`
- `faceMorph`
- `faceTexture.enabled`

## Migration Path

1. Render procedural 3D avatar from config.
2. Replace body primitives with base `.glb`.
3. Replace hair, clothes, shoes with part `.glb` assets.
4. Apply `faceMorph` to BlendShape-like controls.
5. Project face texture into material or UV texture.
6. Export the same result through the GLB pipeline.
