// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/oneme"
import topbar from "../vendor/topbar"

const hooks = {
  ...colocatedHooks,
  AvatarPreview: {
    mounted() {
      this.handleEvent("face_mapping_cleared", () => window.onemeThreePreview?.clearFaceImage())
      this.handleEvent("avatar_saved", payload => {
        if (window.parent === window) return
        const targetOrigin = this.el.dataset.parentOrigin || window.location.origin
        window.parent.postMessage({source: "oneme", type: "avatar_saved", ...payload}, targetOrigin)
      })
      this.syncPreview()
    },
    updated() {
      this.syncPreview()
    },
    syncPreview() {
      try {
        const config = JSON.parse(this.el.dataset.config || "{}")
        window.onemeAvatarConfig = config
        window.dispatchEvent(new CustomEvent("oneme:avatar-config", {detail: config}))
      } catch (_error) {
        console.warn("oneme: invalid avatar config")
      }
    }
  },
  FacePhoto: {
    mounted() {
      this.handleChange = event => handleFacePhoto(event.target, this)
      this.el.addEventListener("change", this.handleChange)
    },
    destroyed() {
      this.el.removeEventListener("change", this.handleChange)
    }
  },
  ExportGlb: {
    mounted() {
      this.handleClick = async () => {
        const status = document.querySelector("#export-status")
        const config = window.onemeAvatarConfig || {}
        if (status) status.textContent = "GLBを生成しています..."

        try {
          await window.onemeThreePreview?.exportGlb(config, "oneme-avatar.glb")
          if (status) status.textContent = "GLBを保存しました。"
        } catch (error) {
          console.error(error)
          if (status) status.textContent = "GLBの生成に失敗しました。"
        }
      }
      this.el.addEventListener("click", this.handleClick)
    },
    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
    }
  },
  ExportFbx: {
    mounted() {
      this.handleClick = () => runServerExport("fbx", "FBX", "oneme-avatar.fbx")
      this.el.addEventListener("click", this.handleClick)
    },
    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
    }
  },
  ExportVrm: {
    mounted() {
      this.handleClick = () => runServerExport("vrm", "VRM", "oneme-avatar.vrm")
      this.el.addEventListener("click", this.handleClick)
    },
    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
    }
  }
}

async function runServerExport(format, label, filename) {
  const status = document.querySelector("#export-status")
  const config = window.onemeAvatarConfig || {}
  if (status) status.textContent = `${label}変換ジョブを実行しています...`

  try {
    const includeFaceTexture = config.faceTexture?.exportConsent === true
    const response = await fetch("/api/export-jobs", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        avatarConfig: config,
        format,
        faceTextureDataUrl: includeFaceTexture ? window.onemeThreePreview?.getFaceTextureDataUrl() : null
      })
    })
    const payload = await response.json()
    if (!response.ok || payload.status !== "succeeded") throw new Error(payload.errorMessage || payload.error || `${label} export failed`)

    const link = document.createElement("a")
    link.href = payload.modelUrl
    link.download = filename
    link.click()
    if (status) status.textContent = `${label}を保存しました。`
  } catch (error) {
    console.error(error)
    if (status) status.textContent = `${label}の生成に失敗しました。Assimpの設定を確認してください。`
  }
}

function handleFacePhoto(input, hook) {
  const status = document.querySelector("#face-status")
  const consent = document.querySelector("#face-consent")
  const file = input.files?.[0]

  if (!file) return
  if (!consent?.checked) {
    input.value = ""
    if (status) status.textContent = "先に写真の利用同意をチェックしてください。"
    return
  }

  const objectUrl = URL.createObjectURL(file)
  const image = new Image()
  image.onload = async () => {
    const bounds = await detectFaceBounds(image)
    const crop = faceCrop(image, bounds)
    const canvas = document.createElement("canvas")
    canvas.width = 512
    canvas.height = 512
    const context = canvas.getContext("2d")
    context.clearRect(0, 0, 512, 512)
    context.save()
    context.beginPath()
    context.ellipse(256, 256, crop.maskWidth, crop.maskHeight, 0, 0, Math.PI * 2)
    context.clip()
    context.drawImage(image, crop.x, crop.y, crop.size, crop.size, 0, 0, 512, 512)
    context.restore()
    URL.revokeObjectURL(objectUrl)
    window.onemeThreePreview?.setFaceImage(canvas.toDataURL("image/png"))
    const ratio = image.width / image.height
    hook.pushEvent("face_analyzed", {
      face_detected: Boolean(bounds),
      face_morph: {
        widthScale: clamp(0.96 + (ratio - 0.75) * 0.16, 0.88, 1.14),
        heightScale: clamp(1.08 + (0.9 - ratio) * 0.12, 0.94, 1.2),
        depth: clamp(0.42 + ratio * 0.08, 0.42, 0.62)
      }
    })
    if (status) {
      status.textContent = bounds
        ? "顔を検出し、輪郭に沿って切り出してプレビューへマッピングしました。"
        : "顔検出を利用できないため、中央を基準に切り出してプレビューへマッピングしました。"
    }
  }
  image.onerror = () => {
    URL.revokeObjectURL(objectUrl)
    if (status) status.textContent = "写真を読み込めませんでした。別の画像を試してください。"
  }
  image.src = objectUrl
}

async function detectFaceBounds(image) {
  if (!("FaceDetector" in window)) return null

  try {
    const detector = new window.FaceDetector({fastMode: true, maxDetectedFaces: 1})
    const detections = await detector.detect(image)
    const bounds = detections[0]?.boundingBox

    if (!bounds || bounds.width <= 0 || bounds.height <= 0) return null
    return {x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height}
  } catch (error) {
    console.debug("oneme: face detection unavailable", error)
    return null
  }
}

function faceCrop(image, bounds) {
  const fallbackSize = Math.min(image.width, image.height)
  const size = bounds
    ? Math.min(Math.min(image.width, image.height), Math.max(bounds.width * 1.7, bounds.height * 1.5))
    : fallbackSize
  const centerX = bounds ? bounds.x + bounds.width / 2 : image.width / 2
  const centerY = bounds ? bounds.y + bounds.height / 2 : image.height / 2
  const x = clamp(centerX - size / 2, 0, image.width - size)
  const y = clamp(centerY - size / 2, 0, image.height - size)
  const maskWidth = bounds ? clamp((bounds.width / size) * 512 * 0.82, 160, 230) : 218
  const maskHeight = bounds ? clamp((bounds.height / size) * 512 * 0.86, 190, 248) : 246

  return {x, y, size, maskWidth, maskHeight}
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
