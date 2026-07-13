// Face Landmarker is loaded separately so the Phoenix asset bundle remains
// usable when a browser or network policy cannot load the optional model.
const moduleUrl = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.22/+esm"
const wasmRoot = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.22/wasm"
const modelUrl = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

window.onemeFaceLandmarkerReady = import(moduleUrl)
  .then(async ({FaceLandmarker, FilesetResolver}) => {
    const vision = await FilesetResolver.forVisionTasks(wasmRoot)
    const options = {
      baseOptions: {modelAssetPath: modelUrl, delegate: "GPU"},
      runningMode: "IMAGE",
      numFaces: 1,
      outputFaceBlendshapes: false,
      outputFacialTransformationMatrixes: false
    }

    try {
      return await FaceLandmarker.createFromOptions(vision, options)
    } catch (_error) {
      return FaceLandmarker.createFromOptions(vision, {
        ...options,
        baseOptions: {modelAssetPath: modelUrl, delegate: "CPU"}
      })
    }
  })
  .catch(error => {
    console.debug("oneme: optional face landmarks unavailable", error)
    return null
  })
