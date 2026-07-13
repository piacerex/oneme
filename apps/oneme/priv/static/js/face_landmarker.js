// Face Landmarker is loaded separately so the Phoenix asset bundle remains
// usable when a browser or network policy cannot load the optional model.
const visionVersion = "0.10.21"
const moduleUrl = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${visionVersion}/vision_bundle.mjs`
const wasmRoot = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${visionVersion}/wasm`
const modelUrl = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

window.onemeFaceLandmarkerStatus = {
  state: "loading",
  moduleUrl,
  wasmRoot,
  modelUrl
}

window.onemeFaceLandmarkerReady = import(moduleUrl)
  .then(async ({FaceLandmarker, FilesetResolver}) => {
    if (!FaceLandmarker || !FilesetResolver) {
      throw new Error("MediaPipe Vision exports are unavailable")
    }

    const vision = await FilesetResolver.forVisionTasks(wasmRoot)
    const options = {
      baseOptions: {modelAssetPath: modelUrl, delegate: "GPU"},
      runningMode: "IMAGE",
      numFaces: 1,
      outputFaceBlendshapes: false,
      outputFacialTransformationMatrixes: false
    }

    try {
      const landmarker = await FaceLandmarker.createFromOptions(vision, options)
      window.onemeFaceLandmarkerStatus = {state: "ready", delegate: "GPU", visionVersion}
      return landmarker
    } catch (_error) {
      const landmarker = await FaceLandmarker.createFromOptions(vision, {
        ...options,
        baseOptions: {modelAssetPath: modelUrl, delegate: "CPU"}
      })
      window.onemeFaceLandmarkerStatus = {state: "ready", delegate: "CPU", visionVersion}
      return landmarker
    }
  })
  .catch(error => {
    console.debug("oneme: optional face landmarks unavailable", error)
    window.onemeFaceLandmarkerStatus = {
      state: "unavailable",
      visionVersion,
      message: error?.message || String(error)
    }
    return null
  })
