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
      this.mountPreview()
      this.handleEvent("face_mapping_cleared", () => window.onemeThreePreview?.clearFaceImage())
      this.handleEvent("avatar_saved", payload => {
        if (window.parent === window) return
        const targetOrigin = this.el.dataset.parentOrigin || window.location.origin
        window.parent.postMessage({source: "oneme", type: "avatar_saved", appId: this.el.dataset.appId || null, ...payload}, targetOrigin)
      })
      this.syncPreview()
    },
    updated() {
      this.mountPreview()
      this.syncPreview()
    },
    mountPreview() {
      const mount = () => window.onemeThreePreview?.mount(this.el)

      if (window.onemeThreePreview) {
        mount()
      } else {
        window.addEventListener("oneme:preview-ready", mount, {once: true})
      }
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
  FaceCompletion: {
    mounted() {
      this.handleClick = () => completeFaceProfile(this)
      this.el.addEventListener("click", this.handleClick)
    },
    destroyed() {
      this.el.removeEventListener("click", this.handleClick)
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

async function completeFaceProfile(hook) {
  const status = document.querySelector("#face-status")
  const faceTextureDataUrl = window.onemeThreePreview?.getFaceTextureDataUrl()
  const config = window.onemeAvatarConfig || {}
  const calibration = config.faceAnalysis?.calibration || window.onemeThreePreview?.getFaceCalibration?.() || {}

  if (!faceTextureDataUrl) {
    if (status) status.textContent = "先に正面の顔写真をマッピングしてください。"
    return
  }

  hook.el.disabled = true
  if (status) status.textContent = "正面画像から側面・背面を補完しています..."

  try {
    const response = await fetch("/api/face-completion", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({faceTextureDataUrl, calibration})
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.message || payload.error || "face completion failed")

    window.onemeThreePreview?.setFaceCompletion(payload.imageDataUrl)
    if (status) status.textContent = "側面・背面の補完をプレビューへ反映しました。"
  } catch (error) {
    console.error(error)
    if (status) status.textContent = "側面・背面の補完に失敗しました。設定を確認してください。"
  } finally {
    hook.el.disabled = false
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
    const geometry = await detectFaceGeometry(image)
    const bounds = geometry?.bounds || null
    const calibration = calibrateFaceTexture(image, bounds, geometry?.landmarks || null)
    URL.revokeObjectURL(objectUrl)

    window.onemeThreePreview?.setFaceImage(calibration.dataUrl, calibration.metadata)
    const faceColors = estimateFaceColors(calibration.canvas.getContext("2d"))
    const ratio = bounds ? bounds.width / Math.max(bounds.height, 1) : image.width / image.height
    hook.pushEvent("face_analyzed", {
      face_detected: Boolean(bounds),
      face_colors: faceColors,
      face_morph: {
        widthScale: calibration.morph.widthScale,
        heightScale: calibration.morph.heightScale,
        depth: clamp(0.46 + ratio * 0.12, 0.42, 0.66)
      },
      face_calibration: calibration.metadata
    })
    if (status) {
      status.textContent = bounds
        ? geometry?.landmarks
          ? "目の傾きを補正し、目・鼻・口を基準に正面へマッピングしました。"
          : "顔を検出し、正面向けに補正してプレビューへマッピングしました。"
        : "顔検出を利用できないため、中央を基準に正面へ補正しました。"
    }
  }
  image.onerror = () => {
    URL.revokeObjectURL(objectUrl)
    if (status) status.textContent = "写真を読み込めませんでした。別の画像を試してください。"
  }
  image.src = objectUrl
}

function estimateFaceColors(context) {
  const skin = averageRegion(context, 150, 180, 212, 210, pixel => {
    const [red, green, blue] = pixel
    return red > 55 && green > 30 && blue > 20 && red >= green * 0.9 && green >= blue * 0.82 && red - blue > 18
  })
  const hair = averageRegion(context, 130, 42, 252, 150, pixel => {
    const brightness = (pixel[0] + pixel[1] + pixel[2]) / 3
    return brightness < 155
  })

  return {
    skin: rgbToHex(skin || [201, 143, 111]),
    hair: rgbToHex(hair || [47, 33, 24])
  }
}

function averageRegion(context, x, y, width, height, include) {
  const pixels = context.getImageData(x, y, width, height).data
  const total = [0, 0, 0]
  let count = 0

  for (let index = 0; index < pixels.length; index += 4) {
    if (pixels[index + 3] < 20) continue
    const pixel = [pixels[index], pixels[index + 1], pixels[index + 2]]
    if (!include(pixel)) continue
    total[0] += pixel[0]
    total[1] += pixel[1]
    total[2] += pixel[2]
    count += 1
  }

  return count ? total.map(value => Math.round(value / count)) : null
}

function rgbToHex(rgb) {
  return `#${rgb.map(value => clamp(Math.round(value), 0, 255).toString(16).padStart(2, "0")).join("")}`
}

async function detectFaceGeometry(image) {
  const bounds = await detectFaceBounds(image)
  const landmarks = await detectFaceLandmarks(image)
  return {bounds: bounds || landmarks?.bounds || null, landmarks: landmarks?.points || null}
}

async function detectFaceLandmarks(image) {
  try {
    const landmarker = await window.onemeFaceLandmarkerReady
    const result = landmarker?.detect(image)
    const points = result?.faceLandmarks?.[0]
    if (!points || points.length < 468) return null

    const mapped = landmarkPoints(points, image)
    return {points: mapped, bounds: landmarkBounds(mapped)}
  } catch (error) {
    console.debug("oneme: face landmark detection unavailable", error)
    return null
  }
}

function landmarkPoints(points, image) {
  const point = index => ({x: points[index].x * image.width, y: points[index].y * image.height})
  const average = indexes => ({
    x: indexes.reduce((total, index) => total + point(index).x, 0) / indexes.length,
    y: indexes.reduce((total, index) => total + point(index).y, 0) / indexes.length
  })
  const eyes = [average([33, 133]), average([263, 362])].sort((left, right) => left.x - right.x)

  return {
    leftEye: eyes[0],
    rightEye: eyes[1],
    nose: point(1),
    mouth: average([13, 14, 61, 291]),
    chin: point(152),
    forehead: point(10),
    leftCheek: point(234),
    rightCheek: point(454)
  }
}

function landmarkBounds(points) {
  const values = Object.values(points)
  const xs = values.map(point => point.x)
  const ys = values.map(point => point.y)
  const x = Math.min(...xs)
  const y = Math.min(...ys)
  return {x, y, width: Math.max(...xs) - x, height: Math.max(...ys) - y}
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

function calibrateFaceTexture(image, bounds, landmarks) {
  const canvas = document.createElement("canvas")
  canvas.width = 512
  canvas.height = 512
  const context = canvas.getContext("2d")
  context.clearRect(0, 0, 512, 512)

  const fallback = faceCrop(image, bounds)
  const leftEye = landmarks?.leftEye
  const rightEye = landmarks?.rightEye
  const hasEyes = leftEye && rightEye && Math.abs(rightEye.x - leftEye.x) > 1
  let eyeCenter = null
  let transformScale = 1
  let eyeAngle = 0
  const targetEyeCenter = {x: 256, y: 226}

  if (hasEyes) {
    eyeCenter = {x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2}
    const eyeDistance = Math.hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
    eyeAngle = Math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x)
    const targetEyeDistance = 154
    transformScale = targetEyeDistance / eyeDistance

    context.save()
    context.translate(targetEyeCenter.x, targetEyeCenter.y)
    context.rotate(-eyeAngle)
    context.scale(transformScale, transformScale)
    context.translate(-eyeCenter.x, -eyeCenter.y)
    context.drawImage(image, 0, 0)
    context.restore()
  } else {
    context.drawImage(image, fallback.x, fallback.y, fallback.size, fallback.size, 0, 0, 512, 512)
  }

  // Keep only the calibrated face oval. The front hemisphere uses this alpha
  // edge to fade into the procedural head at the cheeks and jaw.
  const faceCenter = landmarks?.nose || {x: 256, y: 270}
  const maskCenterX = 256
  const maskCenterY = hasEyes ? 278 : 256
  const maskWidth = hasEyes ? 218 : fallback.maskWidth
  const maskHeight = hasEyes ? 246 : fallback.maskHeight
  context.save()
  context.globalCompositeOperation = "destination-in"
  context.beginPath()
  context.ellipse(maskCenterX, maskCenterY, maskWidth, maskHeight, 0, 0, Math.PI * 2)
  context.fill()
  context.restore()

  const sourceBounds = bounds || {
    x: image.width / 2 - fallback.size / 2,
    y: image.height / 2 - fallback.size / 2,
    width: fallback.size,
    height: fallback.size
  }
  const sourceWidth = Math.max(sourceBounds.width, 1)
  const sourceHeight = Math.max(sourceBounds.height, 1)
  const morph = {
    widthScale: clamp(sourceWidth / Math.max(sourceHeight * 0.82, 1), 0.88, 1.14),
    heightScale: clamp(sourceHeight / Math.max(sourceWidth * 1.08, 1), 0.94, 1.2)
  }

  const mapPoint = hasEyes
    ? point => {
        const dx = point.x - eyeCenter.x
        const dy = point.y - eyeCenter.y
        const cosine = Math.cos(-eyeAngle)
        const sine = Math.sin(-eyeAngle)
        return {
          x: targetEyeCenter.x + transformScale * (dx * cosine - dy * sine),
          y: targetEyeCenter.y + transformScale * (dx * sine + dy * cosine)
        }
      }
    : point => ({
        x: ((point.x - fallback.x) / Math.max(fallback.size, 1)) * 512,
        y: ((point.y - fallback.y) / Math.max(fallback.size, 1)) * 512
      })

  const mappedLandmarks = landmarks
    ? Object.fromEntries(
        Object.entries(landmarks).map(([key, point]) => [key, normalizePoint(mapPoint(point))])
      )
    : {}

  return {
    canvas,
    dataUrl: canvas.toDataURL("image/png"),
    morph,
    metadata: {
      version: 1,
      orientation: hasEyes ? "eye-line-corrected" : "fallback",
      mappedLandmarks,
      sourceBounds: normalizeRect(sourceBounds, image)
    },
    faceCenter
  }
}

function normalizePoint(point) {
  return point ? {x: Number(point.x.toFixed(4)), y: Number(point.y.toFixed(4))} : null
}

function normalizeRect(rect, image) {
  return {
    x: Number((rect.x / image.width).toFixed(4)),
    y: Number((rect.y / image.height).toFixed(4)),
    width: Number((rect.width / image.width).toFixed(4)),
    height: Number((rect.height / image.height).toFixed(4))
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
