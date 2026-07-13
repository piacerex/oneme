# ランタイム検証

## Webビューア

Phoenixを起動した状態で、次のURLを開く。

```text
/model-viewer.html?model_url=/exports/<folder>/avatar.glb
/model-viewer.html?model_url=/exports/<folder>/avatar.vrm
/model-viewer.html?model_url=/exports/<folder>/avatar.fbx
```

モデルURLの代わりに、画面のローカルファイル入力から`.glb`、`.vrm`、`.fbx`を選択できる。
VRMは`@pixiv/three-vrm`の`VRMLoaderPlugin`を登録し、`VRMC_vrm`と`VRMC_springBone`を
読み込んだシーンへ接続する。FBXはThree.jsの材質差を吸収する表示用フォールバックを適用する。

2026-07-13のローカル検証では、次を確認した。

- GLB: HTTP 200、7 meshes、Three.js `GLTFLoader`で読み込み完了
- FBX: HTTP 200、7 meshes、Three.js `FBXLoader`で読み込み完了
- VRM: HTTP 200、7 meshes、`VRMC_vrm`／`VRMC_springBone`を検出し、`hasVrm: true`で読み込み完了

## VRM生成器の不変条件

`JOINTS_0`は`skin.joints`のローカルインデックスを参照する。glTFノード番号を直接
格納してはいけない。次のコマンドで、生成されたVRMの参照範囲とVRM 1.0メタデータを検査する。

```bash
python3 apps/oneme/priv/exporter/validate_glb.py \
  --input apps/oneme/priv/static/exports/<folder>/avatar.vrm \
  --require-vrm
```

## 外部ランタイム

Unity、VRMビューア、Blender、主要DCCの実機検証は、対象ランタイムを導入した環境で行う。
このワークスペースではUnity／Blender実行ファイルを確認できないため、Webビューアの成功を
外部ランタイムの互換性完了とは扱わない。

Blenderを使うFBX変換は、次のようにバックエンドを選択する。

```bash
ONEME_FBX_BACKEND=blender \
ONEME_BLENDER_BIN=/path/to/blender \
mix phx.server
```

Unity側は`packages/sdk-unity`をPackage Managerへ追加し、`Avatar Viewer`サンプルを
インポートして検証する。サンプルは公開モデルAPIからバイナリを取得し、glTFastでGLB/VRMの
メインシーンを展開する。VRMのhumanoid、表情、揺れ物の意味論はglTFast単体の検証範囲外で、
VRM対応ランタイムを追加した実機検証が必要になる。

Blenderバックエンドは生成済みOBJを直接読み込むため、Assimpなしで次の変換経路を検証できる。

```text
avatar.json + face.png -> create_avatar_obj.py -> avatar.obj -> Blender FBX exporter -> avatar.fbx
```
