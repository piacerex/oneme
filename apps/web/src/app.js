const appState = {
  version: "0.1.0",
  avatarId: "local-demo",
  style: "semi_real_lightweight",
  parts: {
    baseBody: "base_body.default",
    face: "face.soft_01",
    hair: "hair.short_01",
    top: "top.basic_01",
    bottom: "bottom.basic_01",
    shoes: "shoes.basic_01",
    accessory: "accessory.none"
  },
  colors: {
    skin: "#c98f6f",
    hair: "#2f2118"
  },
  source: {
    kind: "manual"
  }
};

const partOptions = {
  face: [
    { id: "face.soft_01", label: "Soft" },
    { id: "face.sharp_01", label: "Sharp" },
    { id: "face.round_01", label: "Round" }
  ],
  hair: [
    { id: "hair.short_01", label: "Short" },
    { id: "hair.medium_01", label: "Medium" },
    { id: "hair.long_01", label: "Long" },
    { id: "hair.none", label: "Bald" }
  ],
  top: [
    { id: "top.basic_01", label: "Basic Tee" },
    { id: "top.hoodie_01", label: "Hoodie" },
    { id: "top.jacket_01", label: "Jacket" }
  ],
  bottom: [
    { id: "bottom.basic_01", label: "Basic Pants" },
    { id: "bottom.tapered_01", label: "Tapered Pants" },
    { id: "bottom.skirt_01", label: "Skirt" }
  ],
  shoes: [
    { id: "shoes.basic_01", label: "Basic Shoes" },
    { id: "shoes.sneaker_01", label: "Sneakers" },
    { id: "shoes.boot_01", label: "Boots" }
  ],
  accessory: [
    { id: "accessory.none", label: "None" },
    { id: "accessory.glasses_round_01", label: "Round Glasses" },
    { id: "accessory.hat_cap_01", label: "Cap" }
  ]
};

const previewCanvas = document.querySelector("#avatar-preview");
const configOutput = document.querySelector("#config-output");
const form = document.querySelector("#avatar-form");
const saveButton = document.querySelector("#save-avatar");
const loadButton = document.querySelector("#load-avatar");
const exportButton = document.querySelector("#export-glb");
const downloadGlbLink = document.querySelector("#download-glb");
const saveStatus = document.querySelector("#save-status");
const exportOutput = document.querySelector("#export-output");
const faceConsent = document.querySelector("#face-consent");
const facePhoto = document.querySelector("#face-photo");
const analyzeFaceButton = document.querySelector("#analyze-face");
const clearFaceButton = document.querySelector("#clear-face");
const faceStatus = document.querySelector("#face-status");
const faceResult = document.querySelector("#face-result");
const ctx = previewCanvas.getContext("2d");
const storageKey = "oneme.avatars";
const exportJobsKey = "oneme.exportJobs";
const exportCacheKey = "oneme.exportCache";
let faceAnalysisCounter = 0;
let currentPhotoUrl = null;
let currentModelUrl = null;

function renderConfig() {
  configOutput.textContent = JSON.stringify(appState, null, 2);
}

function renderExportJob(job = getLatestExportJob()) {
  exportOutput.textContent = job ? JSON.stringify(job, null, 2) : "No export job yet.";
}

function populateSelect(name) {
  const select = document.querySelector(`#${name}-select`);
  const options = partOptions[name];

  for (const option of options) {
    const element = document.createElement("option");
    element.value = option.id;
    element.textContent = option.label;
    select.append(element);
  }

  select.value = appState.parts[name];
}

function drawCapsule(x, y, width, height, color) {
  const radius = width / 2;

  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.fill();
}

function drawAvatar() {
  const { width, height } = previewCanvas;
  const centerX = width / 2;
  const skin = appState.colors.skin;
  const hair = appState.colors.hair;
  const topColor = topPalette[appState.parts.top] ?? "#347f7b";
  const bottomColor = bottomPalette[appState.parts.bottom] ?? "#363d49";
  const shoeColor = shoePalette[appState.parts.shoes] ?? "#222222";

  ctx.clearRect(0, 0, width, height);

  const background = ctx.createLinearGradient(0, 0, width, height);
  background.addColorStop(0, "#f7f1e8");
  background.addColorStop(1, "#dce8e4");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, width, height);

  ctx.fillStyle = "rgba(0, 0, 0, 0.12)";
  ctx.beginPath();
  ctx.ellipse(centerX, 850, 160, 34, 0, 0, Math.PI * 2);
  ctx.fill();

  drawCapsule(centerX - 56, 600, 46, 220, bottomColor);
  drawCapsule(centerX + 10, 600, 46, 220, bottomColor);
  drawCapsule(centerX - 76, 802, 70, 34, shoeColor);
  drawCapsule(centerX + 6, 802, 70, 34, shoeColor);

  drawCapsule(centerX - 106, 352, 212, 270, topColor);
  drawCapsule(centerX - 154, 370, 54, 210, topColor);
  drawCapsule(centerX + 100, 370, 54, 210, topColor);
  drawCapsule(centerX - 165, 560, 52, 64, skin);
  drawCapsule(centerX + 113, 560, 52, 64, skin);

  drawCapsule(centerX - 46, 304, 92, 82, skin);
  drawFace(centerX, 230, skin);
  drawHair(centerX, 188, hair);
  drawAccessory(centerX, 230);
}

function drawFace(centerX, y, skin) {
  const faceShape = appState.parts.face;
  const width = faceShape.includes("round") ? 150 : faceShape.includes("sharp") ? 126 : 140;
  const height = faceShape.includes("sharp") ? 170 : 154;

  ctx.fillStyle = skin;
  ctx.beginPath();
  ctx.ellipse(centerX, y, width / 2, height / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = "#25211d";
  ctx.beginPath();
  ctx.ellipse(centerX - 28, y - 8, 7, 10, 0, 0, Math.PI * 2);
  ctx.ellipse(centerX + 28, y - 8, 7, 10, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = "rgba(37, 33, 29, 0.7)";
  ctx.lineWidth = 5;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(centerX - 22, y + 44);
  ctx.quadraticCurveTo(centerX, y + 58, centerX + 22, y + 44);
  ctx.stroke();
}

function drawHair(centerX, y, color) {
  if (appState.parts.hair === "hair.none") return;

  ctx.fillStyle = color;
  ctx.beginPath();

  if (appState.parts.hair === "hair.long_01") {
    ctx.roundRect(centerX - 86, y - 42, 172, 190, 64);
  } else if (appState.parts.hair === "hair.medium_01") {
    ctx.roundRect(centerX - 82, y - 48, 164, 124, 58);
  } else {
    ctx.roundRect(centerX - 76, y - 52, 152, 92, 50);
  }

  ctx.fill();

  ctx.fillStyle = appState.colors.skin;
  ctx.beginPath();
  ctx.ellipse(centerX, y + 42, 68, 66, 0, 0, Math.PI * 2);
  ctx.fill();
}

function drawAccessory(centerX, y) {
  if (appState.parts.accessory === "accessory.glasses_round_01") {
    ctx.strokeStyle = "#1f2423";
    ctx.lineWidth = 7;
    ctx.beginPath();
    ctx.arc(centerX - 30, y - 6, 24, 0, Math.PI * 2);
    ctx.arc(centerX + 30, y - 6, 24, 0, Math.PI * 2);
    ctx.moveTo(centerX - 6, y - 6);
    ctx.lineTo(centerX + 6, y - 6);
    ctx.stroke();
  }

  if (appState.parts.accessory === "accessory.hat_cap_01") {
    ctx.fillStyle = "#8f3d36";
    ctx.beginPath();
    ctx.roundRect(centerX - 82, y - 110, 164, 58, 24);
    ctx.fill();
    drawCapsule(centerX + 36, y - 72, 92, 24, "#8f3d36");
  }
}

function updateFromForm(event) {
  const target = event.target;
  if (!(target instanceof HTMLSelectElement || target instanceof HTMLInputElement)) return;

  if (target.name === "skin") {
    appState.colors.skin = target.value;
  } else if (target.name === "hairColor") {
    appState.colors.hair = target.value;
  } else if (target.name in appState.parts) {
    appState.parts[target.name] = target.value;
  }

  render();
}

function cloneConfig() {
  return JSON.parse(JSON.stringify(appState));
}

function getSavedAvatars() {
  const raw = window.localStorage.getItem(storageKey);
  if (!raw) return [];

  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function getJsonArray(key) {
  const raw = window.localStorage.getItem(key);
  if (!raw) return [];

  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function getJsonObject(key) {
  const raw = window.localStorage.getItem(key);
  if (!raw) return {};

  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function saveAvatar() {
  const saved = getSavedAvatars();
  const avatar = {
    ...cloneConfig(),
    avatarId: `local-${Date.now()}`,
    savedAt: new Date().toISOString()
  };

  saved.unshift(avatar);
  window.localStorage.setItem(storageKey, JSON.stringify(saved.slice(0, 10)));

  appState.avatarId = avatar.avatarId;
  saveStatus.textContent = `Saved ${avatar.avatarId}`;
  render();
}

function getLatestExportJob() {
  return getJsonArray(exportJobsKey)[0] ?? null;
}

function saveExportJob(job) {
  const jobs = getJsonArray(exportJobsKey).filter((item) => item.id !== job.id);
  jobs.unshift(job);
  window.localStorage.setItem(exportJobsKey, JSON.stringify(jobs.slice(0, 20)));
  renderExportJob(job);
}

function saveExportCache(cacheKey, modelBase64) {
  const cache = getJsonObject(exportCacheKey);
  cache[cacheKey] = {
    modelBase64,
    cachedAt: new Date().toISOString()
  };
  window.localStorage.setItem(exportCacheKey, JSON.stringify(cache));
}

function getExportCache(cacheKey) {
  return getJsonObject(exportCacheKey)[cacheKey] ?? null;
}

function getVisualConfig(config) {
  return {
    style: config.style,
    parts: config.parts,
    colors: config.colors
  };
}

function createCacheKey(config) {
  return stableStringify(getVisualConfig(config));
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function resolveAvatarParts(config) {
  const requiredFields = ["baseBody", "face", "hair", "top", "bottom", "shoes", "accessory"];

  return requiredFields.map((field) => {
    const partId = config.parts[field];
    if (!partId) throw new Error(`Missing required part: ${field}`);

    const category = partId.split(".")[0];
    return {
      field,
      partId,
      category,
      assetPath: `assets/parts/${category}/${partId.replaceAll(".", "-")}.glb`,
      required: true,
      status: "placeholder"
    };
  });
}

function exportGlb() {
  const avatarConfig = cloneConfig();
  const cacheKey = createCacheKey(avatarConfig);
  const cached = getExportCache(cacheKey);
  const job = {
    id: `export-local-${Date.now()}`,
    status: "queued",
    cacheKey,
    avatarConfig,
    createdAt: new Date().toISOString()
  };

  saveExportJob(job);
  saveStatus.textContent = "Export queued";

  window.setTimeout(() => runExportJob(job, cached), 80);
}

function runExportJob(job, cached) {
  try {
    const runningJob = {
      ...job,
      status: "running",
      resolvedParts: resolveAvatarParts(job.avatarConfig)
    };
    saveExportJob(runningJob);

    const modelBase64 =
      cached?.modelBase64 ??
      bytesToBase64(createGlbBytes(runningJob.avatarConfig, runningJob.resolvedParts));

    if (!cached) saveExportCache(runningJob.cacheKey, modelBase64);

    const modelBlob = base64ToBlob(modelBase64, "model/gltf-binary");
    setDownloadUrl(modelBlob, `${runningJob.avatarConfig.avatarId}.glb`);

    saveExportJob({
      ...runningJob,
      status: "succeeded",
      modelUrl: downloadGlbLink.href,
      cacheHit: Boolean(cached),
      finishedAt: new Date().toISOString()
    });
    saveStatus.textContent = cached ? "Export reused cached GLB" : "Exported GLB";
  } catch (error) {
    saveExportJob({
      ...job,
      status: "failed",
      error: error instanceof Error ? error.message : String(error),
      finishedAt: new Date().toISOString()
    });
    saveStatus.textContent = "Export failed";
  }
}

function setDownloadUrl(blob, fileName) {
  if (currentModelUrl) URL.revokeObjectURL(currentModelUrl);
  currentModelUrl = URL.createObjectURL(blob);
  downloadGlbLink.href = currentModelUrl;
  downloadGlbLink.download = fileName;
  downloadGlbLink.hidden = false;
}

function createGlbBytes(config, resolvedParts) {
  const gltf = {
    asset: {
      version: "2.0",
      generator: "oneme local MVP exporter",
      extras: {
        oneme: {
          config,
          resolvedParts
        }
      }
    },
    scenes: [{ nodes: [] }],
    scene: 0,
    nodes: []
  };

  const jsonBytes = new TextEncoder().encode(JSON.stringify(gltf));
  const paddedJsonBytes = padBytes(jsonBytes, 0x20);
  const totalLength = 12 + 8 + paddedJsonBytes.length;
  const bytes = new Uint8Array(totalLength);
  const view = new DataView(bytes.buffer);

  view.setUint32(0, 0x46546c67, true);
  view.setUint32(4, 2, true);
  view.setUint32(8, totalLength, true);
  view.setUint32(12, paddedJsonBytes.length, true);
  view.setUint32(16, 0x4e4f534a, true);
  bytes.set(paddedJsonBytes, 20);

  return bytes;
}

function padBytes(bytes, paddingByte) {
  const paddedLength = Math.ceil(bytes.length / 4) * 4;
  const padded = new Uint8Array(paddedLength);
  padded.fill(paddingByte);
  padded.set(bytes);
  return padded;
}

function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return window.btoa(binary);
}

function base64ToBlob(base64, type) {
  const binary = window.atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return new Blob([bytes], { type });
}

function loadLatestAvatar() {
  const [latest] = getSavedAvatars();
  if (!latest) {
    saveStatus.textContent = "No saved avatar yet";
    return;
  }

  appState.avatarId = latest.avatarId;
  appState.parts = { ...appState.parts, ...latest.parts };
  appState.colors = { ...appState.colors, ...latest.colors };
  appState.source = latest.source ?? { kind: "manual" };

  syncForm();
  saveStatus.textContent = `Loaded ${latest.avatarId}`;
  render();
}

function clearFacePhoto() {
  if (currentPhotoUrl) {
    URL.revokeObjectURL(currentPhotoUrl);
    currentPhotoUrl = null;
  }

  facePhoto.value = "";
  faceResult.hidden = true;
  faceResult.textContent = "";
  faceStatus.textContent = "Photo cleared. Manual creation remains available.";

  if (appState.source.kind === "face_recommendation") {
    appState.source = { kind: "manual" };
    render();
  }
}

function setFaceStatus(message) {
  faceStatus.textContent = message;
}

function analyzeFacePhoto() {
  const [file] = facePhoto.files;

  if (!faceConsent.checked) {
    setFaceStatus("Check consent before analyzing a photo.");
    return;
  }

  if (!file) {
    setFaceStatus("Choose a photo first, or keep using manual creation.");
    return;
  }

  if (!file.type.startsWith("image/")) {
    setFaceStatus("Choose an image file.");
    return;
  }

  if (currentPhotoUrl) URL.revokeObjectURL(currentPhotoUrl);
  currentPhotoUrl = URL.createObjectURL(file);
  setFaceStatus("Analyzing locally in this browser...");

  const image = new Image();
  image.onload = () => {
    const recommendation = recommendFromImage(image);
    URL.revokeObjectURL(currentPhotoUrl);
    currentPhotoUrl = null;
    applyFaceRecommendation(recommendation);
  };
  image.onerror = () => {
    URL.revokeObjectURL(currentPhotoUrl);
    currentPhotoUrl = null;
    setFaceStatus("Could not read this image.");
  };
  image.src = currentPhotoUrl;
}

function recommendFromImage(image) {
  const sampleCanvas = document.createElement("canvas");
  const sampleSize = 96;
  sampleCanvas.width = sampleSize;
  sampleCanvas.height = sampleSize;

  const sampleContext = sampleCanvas.getContext("2d", { willReadFrequently: true });
  sampleContext.drawImage(image, 0, 0, sampleSize, sampleSize);

  const topPixels = sampleContext.getImageData(0, 0, sampleSize, Math.round(sampleSize * 0.32));
  const centerPixels = sampleContext.getImageData(
    Math.round(sampleSize * 0.24),
    Math.round(sampleSize * 0.24),
    Math.round(sampleSize * 0.52),
    Math.round(sampleSize * 0.52)
  );

  const hairColor = averageVisibleColor(topPixels.data, "dark");
  const skinColor = averageVisibleColor(centerPixels.data, "warm");
  const facePreset = pickFacePreset(image.width / image.height, skinColor);
  const hairPreset = pickHairPreset(hairColor);

  return {
    jobId: `face-local-${Date.now()}-${++faceAnalysisCounter}`,
    skinColor,
    hairColor,
    facePreset,
    hairPreset
  };
}

function averageVisibleColor(data, mode) {
  let red = 0;
  let green = 0;
  let blue = 0;
  let count = 0;

  for (let index = 0; index < data.length; index += 4) {
    const alpha = data[index + 3];
    if (alpha < 128) continue;

    const r = data[index];
    const g = data[index + 1];
    const b = data[index + 2];
    const brightness = (r + g + b) / 3;
    const warmth = r - b;

    if (mode === "dark" && brightness > 190) continue;
    if (mode === "warm" && warmth < -10) continue;

    red += r;
    green += g;
    blue += b;
    count += 1;
  }

  if (count === 0) return mode === "dark" ? "#2f2118" : "#c98f6f";

  return rgbToHex(
    Math.round(red / count),
    Math.round(green / count),
    Math.round(blue / count)
  );
}

function rgbToHex(red, green, blue) {
  return `#${[red, green, blue]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("")}`;
}

function pickFacePreset(aspectRatio, skinColor) {
  const brightness = hexBrightness(skinColor);
  if (aspectRatio < 0.78) return "face.sharp_01";
  if (brightness > 190) return "face.round_01";
  return "face.soft_01";
}

function pickHairPreset(hairColor) {
  const brightness = hexBrightness(hairColor);
  if (brightness > 175) return "hair.medium_01";
  if (brightness < 65) return "hair.short_01";
  return "hair.long_01";
}

function hexBrightness(hex) {
  const red = Number.parseInt(hex.slice(1, 3), 16);
  const green = Number.parseInt(hex.slice(3, 5), 16);
  const blue = Number.parseInt(hex.slice(5, 7), 16);
  return (red * 299 + green * 587 + blue * 114) / 1000;
}

function applyFaceRecommendation(recommendation) {
  appState.parts.face = recommendation.facePreset;
  appState.parts.hair = recommendation.hairPreset;
  appState.colors.skin = recommendation.skinColor;
  appState.colors.hair = recommendation.hairColor;
  appState.source = {
    kind: "face_recommendation",
    faceAnalysisJobId: recommendation.jobId
  };

  syncForm();
  renderFaceResult(recommendation);
  setFaceStatus("Recommendation applied. You can adjust every part manually.");
  render();
}

function renderFaceResult(recommendation) {
  faceResult.hidden = false;
  faceResult.innerHTML = `
    <strong>Local recommendation</strong>
    <span>Skin: ${recommendation.skinColor}</span>
    <span>Hair: ${recommendation.hairColor}</span>
    <span>Face: ${recommendation.facePreset}</span>
    <span>Hair part: ${recommendation.hairPreset}</span>
  `;
}

function syncForm() {
  for (const name of Object.keys(partOptions)) {
    document.querySelector(`#${name}-select`).value = appState.parts[name];
  }

  document.querySelector("#skin-color").value = appState.colors.skin;
  document.querySelector("#hair-color").value = appState.colors.hair;
}

function render() {
  drawAvatar();
  renderConfig();
  renderExportJob();
}

const topPalette = {
  "top.basic_01": "#347f7b",
  "top.hoodie_01": "#6f4f8f",
  "top.jacket_01": "#2f3f54"
};

const bottomPalette = {
  "bottom.basic_01": "#363d49",
  "bottom.tapered_01": "#5f665f",
  "bottom.skirt_01": "#7b4c58"
};

const shoePalette = {
  "shoes.basic_01": "#232323",
  "shoes.sneaker_01": "#f4f0ea",
  "shoes.boot_01": "#4a3026"
};

for (const name of Object.keys(partOptions)) {
  populateSelect(name);
}

form.addEventListener("input", updateFromForm);
saveButton.addEventListener("click", saveAvatar);
loadButton.addEventListener("click", loadLatestAvatar);
exportButton.addEventListener("click", exportGlb);
analyzeFaceButton.addEventListener("click", analyzeFacePhoto);
clearFaceButton.addEventListener("click", clearFacePhoto);
render();
