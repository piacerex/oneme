# MVP Parts

## Minimum Part Counts

| Category | Minimum Count | Notes |
| --- | ---: | --- |
| base_body | 1 | Shared body for the MVP. |
| skin_tone | 6 | Stored as color values, not separate meshes. |
| hair | 6 | Include short, medium, long, tied, curly, bald. |
| face | 6 | Existing face presets selected manually or by recommendation. |
| top | 6 | Simple tops with consistent rig compatibility. |
| bottom | 4 | Pants and skirt options. |
| shoes | 4 | Low-detail shoe meshes. |
| accessory | 6 | Glasses, hat, simple items. |

## Initial Part IDs

```text
base_body.default
skin_tone.light_01
skin_tone.medium_01
skin_tone.deep_01
hair.short_01
face.soft_01
top.basic_01
bottom.basic_01
shoes.basic_01
accessory.none
```

## Recommendation Mapping

Face photo analysis maps into these controllable fields:

- `skinTone`
- `hairColor`
- `hairStyle`
- `facePreset`

The MVP does not infer identity, ethnicity, age, or sensitive attributes.
