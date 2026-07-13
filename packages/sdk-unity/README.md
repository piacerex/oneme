# oneme Unity SDK

`Runtime/OnemeAvatarLoader.cs` は公開アバターのモデルAPIを呼び出し、GLBまたはVRMの
バイナリをUnityへ取得します。取得したバイト列は`LastModelBytes`で参照できます。

パッケージにはUnity 2021.3で利用できるglTFast v5.0.0をGit依存として含めています。
`Runtime/OnemeAvatarSceneLoader.cs`を同じGameObjectへ追加し、`AvatarLoader`と必要なら
`Parent`を指定してください。`Load()`はモデル取得からScene展開までを実行し、取得済みの
バイト列だけを展開する場合は`LoadLatestAsync()`、外部取得元のバイト列を展開する場合は
`LoadBytesAsync(byte[])`を使います。

```csharp
public sealed class AvatarScreen : MonoBehaviour
{
    [SerializeField] private OnemeAvatarSceneLoader loader;

    private void Start()
    {
        StartCoroutine(loader.Load());
    }
}
```

`SceneLoaded`は新しいルート、`LoadFailed`はエラーメッセージを通知します。SDKはモデルURL
の解決、HTTPエラー、再読み込み、glTFastによるScene展開を担当します。
