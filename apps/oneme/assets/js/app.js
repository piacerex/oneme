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
  image.onload = () => {
    const size = Math.min(image.width, image.height)
    const x = (image.width - size) / 2
    const y = (image.height - size) / 2
    const canvas = document.createElement("canvas")
    canvas.width = 512
    canvas.height = 512
    const context = canvas.getContext("2d")
    context.clearRect(0, 0, 512, 512)
    context.save()
    context.beginPath()
    context.ellipse(256, 256, 218, 246, 0, 0, Math.PI * 2)
    context.clip()
    context.drawImage(image, x, y, size, size, 0, 0, 512, 512)
    context.restore()
    URL.revokeObjectURL(objectUrl)
    window.onemeThreePreview?.setFaceImage(canvas.toDataURL("image/png"))
    const ratio = image.width / image.height
    hook.pushEvent("face_analyzed", {
      face_morph: {
        widthScale: clamp(0.96 + (ratio - 0.75) * 0.16, 0.88, 1.14),
        heightScale: clamp(1.08 + (0.9 - ratio) * 0.12, 0.94, 1.2),
        depth: clamp(0.42 + ratio * 0.08, 0.42, 0.62)
      }
    })
    if (status) status.textContent = "顔の輪郭に沿って切り出し、プレビューへマッピングしました。"
  }
  image.onerror = () => {
    URL.revokeObjectURL(objectUrl)
    if (status) status.textContent = "写真を読み込めませんでした。別の画像を試してください。"
  }
  image.src = objectUrl
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
