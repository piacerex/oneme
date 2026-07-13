# Avatar Viewer sample

1. Add `packages/sdk-unity` through Unity Package Manager.
2. Import the Package Manager sample named `Avatar Viewer`.
3. Create an empty GameObject and add `OnemeAvatarLoader`, `OnemeAvatarSceneLoader`, and `OnemeAvatarViewer`.
4. Set `Avatar Id`, `Api Base Url`, and `Format` in the Inspector.
5. Start the scene. The sample downloads the public model response and instantiates its GLB or VRM main scene through glTFast.

The sample validates binary retrieval and generic glTF scene instantiation. VRM humanoid,
expression, and spring-bone semantics require a VRM-aware Unity runtime in addition to glTFast.
