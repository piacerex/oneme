# @oneme/sdk-web

最小のWeb SDKです。

```js
import {OnemeClient} from "@oneme/sdk-web"

const client = new OnemeClient({baseUrl: "https://avatars.example.com"})
const publicAvatar = await client.fetchPublicAvatar("42")
const config = await client.fetchAvatarConfig(publicAvatar.avatarId)
```

`fetchAvatar`、`fetchAvatarConfig`、`fetchPublicAvatar`、`createExportJob`、
`fetchExportJob`を提供します。
