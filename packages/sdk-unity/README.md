# oneme Unity SDK

This is the Phase 6 Unity SDK skeleton.

## Install

Use Unity Package Manager and add this folder as a local package:

```text
packages/sdk-unity
```

## Usage

1. Add `OnemeAvatarLoader` to a GameObject.
2. Set `Avatar Id`.
3. Set `Api Base Url`.
4. Set `Format` to `glb` or `vrm`.
5. Call `StartCoroutine(loader.Load())`.
6. For VRM readiness checks, call `StartCoroutine(loader.LoadAnimationCompatibility())`.

The current implementation fetches and parses the avatar model response JSON,
then exposes it as `LastModelResponse`. It can also fetch VRM animation
compatibility into `LastAnimationCompatibility`. The next step is to connect a
GLB runtime importer and instantiate the returned model URL.
