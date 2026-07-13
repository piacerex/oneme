# @oneme/sdk-web

最小のWeb SDKです。

```js
import {OnemeClient} from "@oneme/sdk-web"

const client = new OnemeClient({baseUrl: "https://avatars.example.com"})
const publicAvatar = await client.fetchPublicAvatar("42")
const config = await client.fetchAvatarConfig(publicAvatar.avatarId)
```

`fetchParts`、`fetchAvatar`、`fetchAvatarConfig`、`fetchPublicAvatar`、
`createAvatar`、`updateAvatar`、`createExportJob`、`fetchExportJob`を提供します。

`createExportJob`の`format`には`glb`、`fbx`、`vrm`を指定できます。FBXとVRMは
サーバー側のAssimp変換が必要です。

パーツ台帳は`fetchParts`、保存は`createAvatar`、更新は`updateAvatar`で実行できます。
