# oneme Unity SDK

`Runtime/OnemeAvatarLoader.cs` は公開アバターのモデルAPIを呼び出し、GLBまたはVRMの
バイナリをUnityへ取得します。取得したバイト列は`LastModelBytes`で参照できます。

メッシュをSceneへ展開する場合は、UnityプロジェクトへglTFastなどのglTFランタイムを
追加し、`ModelDownloaded`イベントからバイト列を渡します。SDKはモデルURLの解決、
HTTPエラー、再読み込みを担当します。
