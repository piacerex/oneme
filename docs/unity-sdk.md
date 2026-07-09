# Unity SDK

Phase 6 starts with a Unity Package Manager-compatible skeleton.

## Current Scope

- Package manifest
- Runtime `OnemeAvatarLoader`
- Avatar id field
- Model endpoint template
- UnityWebRequest fetch for the model response

## Next Steps

1. Add a GLB runtime importer dependency.
2. Parse the model response schema.
3. Download the returned `.glb` URL.
4. Instantiate the avatar under the loader GameObject.
5. Add cache policy and reload controls.
6. Add Animator sample integration.
