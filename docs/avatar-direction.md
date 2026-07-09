# Avatar Direction

## Target Style

oneme starts with a single stylized, friendly 3D avatar direction.

- Style: semi-real, approachable, lightweight
- Audience: web, Unity, and event applications that need fast avatar creation
- Shape language: simple silhouettes, readable hair and clothing, low visual noise
- MVP priority: reliable part swapping over high likeness accuracy

## MVP Avatar Structure

The first playable avatar is assembled from these categories:

- base_body
- skin_tone
- hair
- face
- top
- bottom
- shoes
- accessory

## Asset Rules

- Use `.glb` as the primary runtime format.
- Keep every part centered around the avatar root.
- Use meters as the working unit.
- Use one neutral T-pose or A-pose across all body-compatible parts.
- Avoid final-form face reconstruction in the MVP.
- Prefer part recommendations from face analysis before any generative mesh work.

## Phase 0 Decisions

- The first avatar style is semi-real and lightweight.
- The first face photo feature recommends existing parts instead of generating a custom mesh.
- The initial output contract is avatar configuration JSON.
- `.glb` export is a later step built from the same configuration JSON.
