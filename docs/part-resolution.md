# Part Resolution

Part resolution maps avatar configuration IDs to exportable asset records.

## MVP Behavior

The MVP uses placeholder records because production `.glb` parts are not available yet.

Each resolved part includes:

- config field
- part id
- category
- asset path
- required
- status

## Placeholder Asset Path Rules

```text
assets/parts/{category}/{part-id}.glb
```

Dots in part ids are replaced with hyphens.

Example:

```text
hair.short_01 -> assets/parts/hair/hair-short_01.glb
```

## Required Parts

- baseBody
- face
- hair
- top
- bottom
- shoes
- accessory

## Validation

The resolver fails if:

- a required config field is missing
- a part id is empty
- a required category is unknown

The MVP marks missing physical files as `placeholder` instead of failing. Production export must fail on missing assets.
