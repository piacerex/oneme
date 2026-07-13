# 顔写真キャリブレーションと側面・背面補完

## 現在の処理

1. ブラウザ内で顔写真を読み込む。
2. 利用可能ならMediaPipe Face Landmarkerで左右の目、鼻、口、顎を検出する。
3. 左右の目を結ぶ線を水平化し、目の中心を基準に正面用テクスチャを生成する。
4. 正面テクスチャは顔の正面半球だけへ貼り、目・鼻・口が側面や背面へ回り込まないようにする。
5. 検出したランドマークと補正方式だけを`faceAnalysis.calibration`へ保存する。写真バイナリ、data URL、恒久URLは保存しない。

MediaPipeが利用できない場合は、FaceDetectorの矩形または中央基準へフォールバックする。この場合は精度が下がるため、画面のステータス表示で区別する。

## 側面・背面のAI補完

`ONEME_OPENAI_API_KEY`を設定すると、`POST /api/face-completion`を利用できる。入力は利用同意後にブラウザで作ったキャリブレーション済み正面テクスチャだけで、Phoenixはそれをディスクへ保存しない。OpenAI Images APIのedit endpointへ一時送信し、`omni-moderation-latest`で生成結果を審査した後、PNG data URLをレスポンスへ返す。

返されたアトラスはブラウザの背面半球へ一時表示する。GLBのブラウザ書き出しには表示中の補完テクスチャが含まれるが、サーバー側FBX/VRM成果物へ自動保存する前に、別途保持・同意・品質確認の設計が必要である。

## 制約

単一の正面写真から実際の側面・後頭部の形状、髪の流れ、耳、首の後ろを観測することはできない。AI補完は見えていない領域の推定であり、本人と完全一致する3D復元ではない。実プロバイダーを有効にする前に、生成結果の手動確認、削除、保持期限、費用上限、法務・地域要件を決める。

関連するOpenAI公式資料:

- [Image generation and edits](https://developers.openai.com/api/docs/guides/image-generation)
- [Moderation](https://developers.openai.com/api/docs/guides/moderation)
