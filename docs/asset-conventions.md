# Asset Conventions

## Directory Layout

```text
assets/
  avatars/
    base/
  parts/
    hair/
    face/
    top/
    bottom/
    shoes/
    accessory/
  textures/
```

## File Naming

Use lowercase kebab-case.

```text
{category}-{slug}-{variant}.glb
```

Examples:

```text
hair-short-01.glb
top-hoodie-01.glb
accessory-glasses-round-01.glb
```

## Transform Rules

- Root object name: `oneme_root`
- Character forward: positive Z
- Character up: positive Y
- Unit scale: 1 unit = 1 meter
- Root position: `0, 0, 0`
- Runtime part transforms should be identity unless a part explicitly documents an offset.

## Metadata

Each production asset must have metadata in `docs/asset-inventory.md`.

Required metadata:

- asset id
- category
- source
- license
- author
- format
- status
- notes
