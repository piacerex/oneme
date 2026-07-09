# AI Generation MVP

Phase 3 adds an AI-style generation workflow before GLB export and SDK work.
The MVP does not call an external AI provider yet. It creates deterministic
candidates from the Phase 2 face recommendation and the current avatar config,
then keeps the same data contracts a provider-backed implementation can use.

## Scope

- Generate multiple avatar style candidates.
- Recommend existing parts.
- Generate texture candidate metadata and color palettes.
- Apply a selected candidate back into the editable avatar.
- Capture recommendation feedback.

## Out of Scope

- Direct 3D mesh generation.
- Identity reconstruction.
- Sensitive attribute inference.
- Long-term storage of source face photos.

## Safety Rules

- Do not infer ethnicity, age, gender, health, or other sensitive attributes.
- Use face analysis output only as color and style hints.
- Reject prompts that ask for identity matching, celebrity likeness, or protected traits.
- Always route candidates through manual editing before save/export.

## Prompt Template

```text
Create a {stylePreset} avatar texture concept for a semi-real lightweight avatar.
Use these safe hints only:
- skin color family: {skinColor}
- hair color family: {hairColor}
- current parts: {partSummary}

Avoid identity matching, sensitive traits, photoreal reconstruction, and protected attributes.
Return palette colors, texture notes, and recommended existing part ids.
```

## Candidate Styles

- clean
- expressive
- event

## Cache Key

The MVP cache key is based on:

- current avatar visual config
- safe face recommendation hints
- candidate style preset

## Feedback

Feedback records whether a candidate was applied, rejected, or saved after edit.
Future recommendation models can learn from this without storing the original photo.
