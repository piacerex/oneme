import * as THREE from "https://unpkg.com/three@0.160.0/build/three.module.js";
import {OrbitControls} from "https://unpkg.com/three@0.160.0/examples/jsm/controls/OrbitControls.js";
import {FBXLoader} from "https://unpkg.com/three@0.160.0/examples/jsm/loaders/FBXLoader.js";
import {GLTFLoader} from "https://unpkg.com/three@0.160.0/examples/jsm/loaders/GLTFLoader.js";
import {VRMLoaderPlugin} from "https://unpkg.com/@pixiv/three-vrm@3.4.2/lib/three-vrm.module.js";

const root = document.querySelector("[data-model-viewer]");

if (root) {
  const canvasHost = root.querySelector("#model-viewer-canvas");
  const form = root.querySelector("#model-viewer-form");
  const urlInput = root.querySelector("#model-url");
  const formatInput = root.querySelector("#model-format");
  const fileInput = root.querySelector("#model-file");
  const status = root.querySelector("#model-status");
  const formatLabel = root.querySelector("#model-format-label");
  const details = root.querySelector("#model-details");
  const resetButton = root.querySelector("#reset-camera");
  const rotateButton = root.querySelector("#toggle-rotation");

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x101819);
  const camera = new THREE.PerspectiveCamera(32, 1, 0.01, 1000);
  camera.position.set(0, 1.2, 4.4);

  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false});
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;
  canvasHost.replaceChildren(renderer.domElement);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 0.25;
  controls.maxDistance = 100;
  controls.maxPolarAngle = Math.PI * 0.86;

  scene.add(new THREE.HemisphereLight(0xf7fbfa, 0x26302f, 2.4));
  const keyLight = new THREE.DirectionalLight(0xffffff, 3.1);
  keyLight.position.set(3, 5, 4);
  scene.add(keyLight);
  const fillLight = new THREE.DirectionalLight(0x9bd9d0, 1.1);
  fillLight.position.set(-4, 2, -2);
  scene.add(fillLight);

  const floor = new THREE.Mesh(
    new THREE.CircleGeometry(2.2, 64),
    new THREE.MeshStandardMaterial({color: 0x2c3836, roughness: 0.88, metalness: 0.04})
  );
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -0.01;
  scene.add(floor);

  const grid = new THREE.GridHelper(8, 16, 0x3f5a55, 0x263a37);
  grid.position.y = 0;
  grid.material.transparent = true;
  grid.material.opacity = 0.3;
  scene.add(grid);

  const state = {
    modelRoot: null,
    vrm: null,
    frame: null,
    autoRotate: true,
    loadToken: 0,
    objectUrl: null
  };
  const clock = new THREE.Clock();

  form.addEventListener("submit", event => {
    event.preventDefault();
    const url = urlInput.value.trim();
    if (url) loadModel(url, formatInput.value);
  });

  fileInput.addEventListener("change", () => {
    const file = fileInput.files?.[0];
    if (!file) return;

    if (state.objectUrl) URL.revokeObjectURL(state.objectUrl);
    state.objectUrl = URL.createObjectURL(file);
    urlInput.value = file.name;
    loadModel(state.objectUrl, formatInput.value === "auto" ? formatFromPath(file.name) : formatInput.value);
  });

  resetButton.addEventListener("click", () => {
    if (state.frame) applyFrame(state.frame);
  });

  rotateButton.addEventListener("click", () => {
    state.autoRotate = !state.autoRotate;
    rotateButton.setAttribute("aria-pressed", String(state.autoRotate));
    rotateButton.textContent = state.autoRotate ? "回転を停止" : "回転を開始";
  });

  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(canvasHost);
  window.addEventListener("beforeunload", () => {
    resizeObserver.disconnect();
    if (state.objectUrl) URL.revokeObjectURL(state.objectUrl);
    disposeCurrent();
    renderer.dispose();
  });

  window.onemeModelViewer = {
    load: loadModel,
    getState: () => ({
      format: formatLabel.textContent,
      status: status.textContent,
      hasModel: Boolean(state.modelRoot),
      hasVrm: Boolean(state.vrm),
      details: details.textContent
    })
  };

  renderer.setAnimationLoop(render);
  resize();
  setStatus("モデルURLまたはファイルを指定してください。", "idle");

  const initialUrl = new URLSearchParams(window.location.search).get("model_url") ||
    new URLSearchParams(window.location.search).get("url");
  if (initialUrl) {
    urlInput.value = initialUrl;
    loadModel(initialUrl, formatInput.value);
  }

  async function loadModel(source, selectedFormat = "auto") {
    const token = ++state.loadToken;
    const format = selectedFormat === "auto" ? formatFromPath(source) : selectedFormat;
    setStatus(`${format.toUpperCase()}を読み込んでいます...`, "loading");
    formatLabel.textContent = format.toUpperCase();

    try {
      const response = await fetch(source);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const buffer = await response.arrayBuffer();
      if (token !== state.loadToken) return;

      disposeCurrent();
      const basePath = basePathFor(source);
      const parsed = format === "fbx"
        ? {object: new FBXLoader().parse(buffer, basePath), extensions: []}
        : await parseGltf(buffer, basePath, format === "vrm");

      if (token !== state.loadToken) return;
      const model = parsed.vrm?.scene || parsed.object || parsed.scene;
      if (!model) throw new Error("モデルのシーンが空です");

      state.vrm = parsed.vrm || null;
      state.modelRoot = new THREE.Group();
      state.modelRoot.add(model);
      scene.add(state.modelRoot);
      if (format === "fbx") normalizeFbxMaterials(model);
      frameModel(state.modelRoot);

      const meshCount = countMeshes(model);
      const extensions = parsed.extensions || [];
      formatLabel.textContent = state.vrm ? "VRM 1.0" : format.toUpperCase();
      details.textContent = `${meshCount} meshes / ${formatBytes(buffer.byteLength)}${extensions.length ? ` / ${extensions.join(", ")}` : ""}`;
      setStatus("読み込み完了", "ready");
    } catch (error) {
      if (token !== state.loadToken) return;
      disposeCurrent();
      formatLabel.textContent = "ERROR";
      details.textContent = "";
      setStatus(`読み込みに失敗しました: ${error.message}`, "error");
      console.error("oneme model viewer failed", error);
    }
  }

  function parseGltf(buffer, basePath, vrmEnabled) {
    return new Promise((resolve, reject) => {
      const loader = new GLTFLoader();
      if (vrmEnabled) loader.register(parser => new VRMLoaderPlugin(parser));
      loader.parse(buffer, basePath, gltf => {
        resolve({
          object: gltf.scene,
          scene: gltf.scene,
          vrm: gltf.userData.vrm || null,
          extensions: gltf.parser.json.extensionsUsed || []
        });
      }, reject);
    });
  }

  function frameModel(modelRoot) {
    modelRoot.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(modelRoot);
    if (box.isEmpty()) throw new Error("モデルの境界が空です");

    const center = box.getCenter(new THREE.Vector3());
    modelRoot.position.x -= center.x;
    modelRoot.position.y -= box.min.y;
    modelRoot.position.z -= center.z;
    modelRoot.updateMatrixWorld(true);

    const framedBox = new THREE.Box3().setFromObject(modelRoot);
    const size = framedBox.getSize(new THREE.Vector3());
    const framedCenter = framedBox.getCenter(new THREE.Vector3());
    const radius = Math.max(size.x, size.y, size.z, 0.2);
    const distance = Math.max(radius * 2.25, 1.4);
    state.frame = {target: new THREE.Vector3(framedCenter.x, size.y * 0.48, framedCenter.z), distance};
    applyFrame(state.frame);
  }

  function normalizeFbxMaterials(model) {
    const fallbackColors = [0x347f7b, 0xc98f6f, 0x2f2118, 0x363d49, 0x7b4c58];
    let fallbackIndex = 0;
    model.traverse(object => {
      if (!object.isMesh) return;
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      object.material = materials.map(material => {
        if (!material?.color) return material;
        const label = `${object.name} ${material.name}`.toLowerCase();
        const semanticColor = label.includes("skin")
          ? 0xc98f6f
          : label.includes("hair")
            ? 0x2f2118
            : label.includes("bottom")
              ? 0x363d49
              : label.includes("shoe")
                ? 0x232323
                : label.includes("top")
                  ? 0x347f7b
                  : null;
        const lightness = material.color.getHSL({h: 0, s: 0, l: 0}).l;
        const color = semanticColor !== null
          ? semanticColor
          : lightness < 0.04
            ? fallbackColors[fallbackIndex++ % fallbackColors.length]
            : material.color.getHex();
        const normalized = new THREE.MeshBasicMaterial({
          color,
          map: material.map || null,
          side: THREE.DoubleSide,
          transparent: material.transparent,
          opacity: material.opacity
        });
        normalized.name = material.name;
        material.dispose?.();
        return normalized;
      });
    });
  }

  function applyFrame(frame) {
    controls.target.copy(frame.target);
    camera.position.set(frame.target.x, frame.target.y + frame.distance * 0.08, frame.target.z + frame.distance);
    camera.near = Math.max(frame.distance / 100, 0.01);
    camera.far = Math.max(frame.distance * 100, 100);
    camera.updateProjectionMatrix();
    controls.update();
  }

  function disposeCurrent() {
    if (state.modelRoot) {
      disposeObject(state.modelRoot);
      scene.remove(state.modelRoot);
    }
    state.modelRoot = null;
    state.vrm = null;
    state.frame = null;
  }

  function disposeObject(object) {
    object.traverse(child => {
      child.geometry?.dispose();
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      for (const material of materials) {
        if (!material) continue;
        for (const value of Object.values(material)) {
          if (value?.isTexture) value.dispose();
        }
        material.dispose?.();
      }
    });
  }

  function countMeshes(object) {
    let count = 0;
    object.traverse(child => { if (child.isMesh) count += 1; });
    return count;
  }

  function resize() {
    const rect = canvasHost.getBoundingClientRect();
    const width = Math.max(rect.width, 1);
    const height = Math.max(rect.height, 1);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
  }

  function render() {
    const delta = clock.getDelta();
    if (state.vrm) state.vrm.update(delta);
    if (state.autoRotate && state.modelRoot) state.modelRoot.rotation.y += delta * 0.28;
    controls.update();
    renderer.render(scene, camera);
  }

  function setStatus(message, type) {
    status.textContent = message;
    status.dataset.state = type;
  }

  function formatFromPath(path) {
    const cleanPath = path.split("?")[0].toLowerCase();
    if (cleanPath.endsWith(".vrm")) return "vrm";
    if (cleanPath.endsWith(".fbx")) return "fbx";
    return "glb";
  }

  function basePathFor(path) {
    if (path.startsWith("blob:")) return "";
    const absolute = new URL(path, window.location.href);
    const slash = absolute.pathname.lastIndexOf("/");
    return `${absolute.origin}${absolute.pathname.slice(0, slash + 1)}`;
  }

  function formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
}
