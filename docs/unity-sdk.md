# Unity SDK

Phase 6 starts with a Unity Package Manager-compatible skeleton.

## Current Scope

- Package manifest
- Runtime `OnemeAvatarLoader`
- Avatar id field
- API base URL and model format fields
- UnityWebRequest fetch for the model response
- Model response parsing into `OnemeModelResponse`
- `BuildModelUrl()` helper for `/api/avatars/:id/model?format=...`
- VRM animation compatibility fetch through
  `/api/avatars/:id/animation_compat?format=...`
- Animation compatibility parsing into `OnemeAnimationCompatibilityResponse`

## Next Steps

1. Add a GLB runtime importer dependency.
2. Download the returned `.glb` URL.
3. Instantiate the avatar under the loader GameObject.
4. Map `OnemeAnimationCompatibilityResponse` to Animator setup guidance.
5. Add cache policy and reload controls.
