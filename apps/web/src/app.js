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
  faceMorph: {
    widthScale: 1,
    heightScale: 1,
    depth: 0.5,
    eyeOffsetY: 0,
    mouthOffsetY: 0
  },
  faceTexture: {
    enabled: false,
    mode: "cutout_overlay"
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
const getModelUrlButton = document.querySelector("#get-model-url");
const generateAiButton = document.querySelector("#generate-ai");
const downloadGlbLink = document.querySelector("#download-glb");
const saveStatus = document.querySelector("#save-status");
const exportOutput = document.querySelector("#export-output");
const aiStatus = document.querySelector("#ai-status");
const aiCandidates = document.querySelector("#ai-candidates");
const faceConsent = document.querySelector("#face-consent");
const facePhoto = document.querySelector("#face-photo");
const mapFaceTexture = document.querySelector("#map-face-texture");
const analyzeFaceButton = document.querySelector("#analyze-face");
const clearFaceButton = document.querySelector("#clear-face");
const faceStatus = document.querySelector("#face-status");
const faceResult = document.querySelector("#face-result");
const ctx = previewCanvas.getContext("2d");
const storageKey = "oneme.avatars";
const exportJobsKey = "oneme.exportJobs";
const exportCacheKey = "oneme.exportCache";
const aiJobsKey = "oneme.aiGenerationJobs";
const recommendationFeedbackKey = "oneme.recommendationFeedback";
let faceAnalysisCounter = 0;
let currentPhotoUrl = null;
let currentModelUrl = null;
let facePreviewImage = null;
let faceCutout = null;
let latestAiJob = null;
let rotationStartedAt = 0;
let currentTurn = 0;

function renderConfig() {
  configOutput.textContent = JSON.stringify(appState, null, 2);
}

function renderExportJob(job = getLatestExportJob()) {
  exportOutput.textContent = job ? JSON.stringify(job, null, 2) : "No export job yet.";
}

function renderAiCandidates(job = latestAiJob) {
  aiCandidates.textContent = "";
  if (!job?.candidates?.length) return;

  for (const candidate of job.candidates) {
    const card = document.createElement("article");
    card.className = "candidate-card";

    const title = document.createElement("h3");
    title.textContent = candidate.stylePreset;

    const notes = document.createElement("p");
    notes.textContent = candidate.textureCandidate.notes;

    const palette = document.createElement("div");
    palette.className = "palette-row";
    for (const color of candidate.textureCandidate.palette) {
      const swatch = document.createElement("span");
      swatch.className = "palette-swatch";
      swatch.style.background = color;
      swatch.title = color;
      palette.append(swatch);
    }

    const safety = document.createElement("small");
    safety.textContent = `Safety: ${candidate.safety.status} - ${candidate.safety.reasons.join(", ")}`;

    const applyButton = document.createElement("button");
    applyButton.type = "button";
    applyButton.textContent = "Apply Candidate";
    applyButton.dataset.candidateId = candidate.id;

    card.append(title, notes, palette, safety, applyButton);
    aiCandidates.append(card);
  }
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

  ctx.save();
  applyAvatarTurnTransform(centerX, 470);

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

  drawHair(centerX, 188, hair);
  drawCapsule(centerX - 46, 304, 92, 82, skin);
  drawFace(centerX, 230, skin);
  drawAccessory(centerX, 230);
  ctx.restore();
  drawFacePhotoReference();
}

function applyAvatarTurnTransform(centerX, pivotY) {
  const scaleX = 0.86 + Math.cos(currentTurn) * 0.14;
  const skew = Math.sin(currentTurn) * 0.045;

  ctx.translate(centerX, pivotY);
  ctx.transform(scaleX, 0, skew, 1, 0, 0);
  ctx.translate(-centerX, -pivotY);
}

function drawFace(centerX, y, skin) {
  const faceShape = appState.parts.face;
  const morph = appState.faceMorph ?? getDefaultFaceMorph();
  const width = (faceShape.includes("round") ? 150 : faceShape.includes("sharp") ? 126 : 140) * morph.widthScale;
  const height = (faceShape.includes("sharp") ? 170 : 154) * morph.heightScale;

  ctx.fillStyle = skin;
  ctx.beginPath();
  ctx.ellipse(centerX, y, width / 2, height / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  drawMappedFaceTexture(centerX, y, width, height);

  const highlight = ctx.createRadialGradient(
    centerX - width * 0.18,
    y - height * 0.2,
    8,
    centerX,
    y,
    width * 0.54
  );
  highlight.addColorStop(0, `rgba(255, 255, 255, ${0.16 + morph.depth * 0.18})`);
  highlight.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = highlight;
  ctx.beginPath();
  ctx.ellipse(centerX, y, width / 2, height / 2, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = "#25211d";
  ctx.beginPath();
  ctx.ellipse(centerX - width * 0.2, y - 8 + morph.eyeOffsetY, 7, 10, 0, 0, Math.PI * 2);
  ctx.ellipse(centerX + width * 0.2, y - 8 + morph.eyeOffsetY, 7, 10, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = "rgba(37, 33, 29, 0.7)";
  ctx.lineWidth = 5;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(centerX - width * 0.16, y + 44 + morph.mouthOffsetY);
  ctx.quadraticCurveTo(centerX, y + 58 + morph.mouthOffsetY, centerX + width * 0.16, y + 44 + morph.mouthOffsetY);
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
  recordSavedAfterAiEdit();
  render();
}

function getLatestExportJob() {
  return getJsonArray(exportJobsKey)[0] ?? null;
}

function getLatestSuccessfulExportJob(avatarId = appState.avatarId) {
  return getJsonArray(exportJobsKey).find(
    (job) => job.status === "succeeded" && job.avatarConfig?.avatarId === avatarId
  );
}

function saveExportJob(job) {
  const jobs = getJsonArray(exportJobsKey).filter((item) => item.id !== job.id);
  jobs.unshift(job);
  window.localStorage.setItem(exportJobsKey, JSON.stringify(jobs.slice(0, 20)));
  renderExportJob(job);
}

function saveAiJob(job) {
  latestAiJob = job;
  const jobs = getJsonArray(aiJobsKey).filter((item) => item.id !== job.id);
  jobs.unshift(job);
  window.localStorage.setItem(aiJobsKey, JSON.stringify(jobs.slice(0, 20)));
  renderAiCandidates(job);
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
    const modelResponse = createAvatarModelResponse(runningJob, Boolean(cached));

    saveExportJob({
      ...runningJob,
      status: "succeeded",
      modelUrl: modelResponse.modelUrl,
      modelResponse,
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

function getAvatarModelUrl() {
  const job = getLatestSuccessfulExportJob();
  if (!job) {
    saveStatus.textContent = "Export a GLB before requesting the model URL";
    return;
  }

  const cached = getExportCache(job.cacheKey);
  if (!cached?.modelBase64) {
    saveStatus.textContent = "Cached model payload is missing. Export again.";
    return;
  }

  const modelBlob = base64ToBlob(cached.modelBase64, "model/gltf-binary");
  setDownloadUrl(modelBlob, `${job.avatarConfig.avatarId}.glb`);

  const modelResponse = createAvatarModelResponse(
    {
      ...job,
      modelUrl: downloadGlbLink.href
    },
    true
  );
  saveExportJob({
    ...job,
    modelUrl: modelResponse.modelUrl,
    modelResponse,
    cacheHit: true
  });
  saveStatus.textContent = "Model URL response refreshed";
}

function createAvatarModelResponse(job, cacheHit) {
  return {
    avatarId: job.avatarConfig.avatarId,
    format: "glb",
    modelUrl: downloadGlbLink.href,
    exportJobId: job.id,
    cacheHit
  };
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
  appState.faceMorph = { ...getDefaultFaceMorph(), ...latest.faceMorph };
  appState.faceTexture = { ...getDefaultFaceTexture(), ...latest.faceTexture, enabled: false };
  appState.source = latest.source ?? { kind: "manual" };

  syncForm();
  saveStatus.textContent = `Loaded ${latest.avatarId}`;
  render();
}

function generateAiCandidates() {
  const avatarConfig = cloneConfig();
  const job = {
    id: `ai-local-${Date.now()}`,
    status: "queued",
    input: {
      avatarConfig,
      safeHints: getSafeAiHints(avatarConfig)
    },
    candidates: [],
    createdAt: new Date().toISOString()
  };

  saveAiJob(job);
  aiStatus.textContent = "Generating local candidates...";
  window.setTimeout(() => runAiGenerationJob(job), 80);
}

function runAiGenerationJob(job) {
  try {
    const rejectedReason = getUnsafeGenerationReason(job.input.safeHints);
    if (rejectedReason) {
      saveAiJob({
        ...job,
        status: "rejected",
        error: rejectedReason,
        finishedAt: new Date().toISOString()
      });
      aiStatus.textContent = rejectedReason;
      return;
    }

    const candidates = createLocalAiCandidates(job.input.avatarConfig, job.input.safeHints);
    saveAiJob({
      ...job,
      status: "succeeded",
      candidates,
      finishedAt: new Date().toISOString()
    });
    aiStatus.textContent = "Generated 3 editable candidates.";
  } catch (error) {
    saveAiJob({
      ...job,
      status: "failed",
      error: error instanceof Error ? error.message : String(error),
      finishedAt: new Date().toISOString()
    });
    aiStatus.textContent = "AI generation failed.";
  }
}

function getSafeAiHints(config) {
  return {
    skinColor: config.colors.skin,
    hairColor: config.colors.hair,
    facePreset: config.parts.face,
    hairPreset: config.parts.hair
  };
}

function getUnsafeGenerationReason(hints) {
  const values = Object.values(hints).join(" ").toLowerCase();
  const blockedTerms = ["celebrity", "identity", "ethnicity", "age", "health"];
  const blocked = blockedTerms.find((term) => values.includes(term));
  return blocked ? `Rejected unsafe generation hint: ${blocked}` : "";
}

function createLocalAiCandidates(config, hints) {
  const basePalette = [hints.skinColor, hints.hairColor];
  const styles = [
    {
      stylePreset: "clean",
      parts: { top: "top.basic_01", accessory: "accessory.none" },
      accent: "#347f7b",
      notes: "Clean everyday texture direction with calm fabric contrast."
    },
    {
      stylePreset: "expressive",
      parts: { top: "top.hoodie_01", accessory: "accessory.glasses_round_01" },
      accent: "#6f4f8f",
      notes: "Expressive social avatar direction with stronger accessory focus."
    },
    {
      stylePreset: "event",
      parts: { top: "top.jacket_01", accessory: "accessory.hat_cap_01" },
      accent: "#8f3d36",
      notes: "Event-ready avatar direction with higher contrast outerwear."
    }
  ];

  return styles.map((style, index) => ({
    id: `candidate-${style.stylePreset}-${index + 1}`,
    stylePreset: style.stylePreset,
    configPatch: {
      parts: {
        ...style.parts,
        face: config.parts.face,
        hair: config.parts.hair
      },
      colors: {
        skin: hints.skinColor,
        hair: tintColor(hints.hairColor, index * 16)
      }
    },
    textureCandidate: {
      palette: [...basePalette, style.accent],
      notes: style.notes
    },
    safety: {
      status: "approved",
      reasons: ["uses safe color hints and existing part ids only"]
    }
  }));
}

function handleCandidateAction(event) {
  const button = event.target.closest("button[data-candidate-id]");
  if (!button) return;

  const candidate = latestAiJob?.candidates?.find((item) => item.id === button.dataset.candidateId);
  if (!candidate) {
    aiStatus.textContent = "Candidate is no longer available.";
    return;
  }

  applyAiCandidate(candidate);
}

function applyAiCandidate(candidate) {
  if (candidate.safety.status !== "approved") {
    recordRecommendationFeedback(candidate, "rejected");
    aiStatus.textContent = "Rejected candidate was not applied.";
    return;
  }

  appState.parts = {
    ...appState.parts,
    ...candidate.configPatch.parts
  };
  appState.colors = {
    ...appState.colors,
    ...candidate.configPatch.colors
  };
  appState.source = {
    kind: "ai_generation",
    aiGenerationJobId: latestAiJob.id,
    aiCandidateId: candidate.id
  };

  recordRecommendationFeedback(candidate, "applied");
  syncForm();
  render();
  aiStatus.textContent = `Applied ${candidate.stylePreset}. You can keep editing before save/export.`;
}

function recordRecommendationFeedback(candidate, action, jobId = latestAiJob?.id ?? "unknown") {
  const feedback = {
    id: `feedback-${Date.now()}`,
    jobId,
    candidateId: candidate.id,
    action,
    createdAt: new Date().toISOString()
  };
  const records = getJsonArray(recommendationFeedbackKey);
  records.unshift(feedback);
  window.localStorage.setItem(recommendationFeedbackKey, JSON.stringify(records.slice(0, 50)));
}

function recordSavedAfterAiEdit() {
  if (appState.source.kind !== "ai_generation") return;

  recordRecommendationFeedback(
    {
      id: appState.source.aiCandidateId
    },
    "saved_after_edit",
    appState.source.aiGenerationJobId
  );
}

function tintColor(hex, amount) {
  const red = clampColor(Number.parseInt(hex.slice(1, 3), 16) + amount);
  const green = clampColor(Number.parseInt(hex.slice(3, 5), 16) + amount);
  const blue = clampColor(Number.parseInt(hex.slice(5, 7), 16) + amount);
  return rgbToHex(red, green, blue);
}

function clampColor(value) {
  return Math.max(0, Math.min(255, value));
}

function clearFacePhoto() {
  if (currentPhotoUrl) {
    URL.revokeObjectURL(currentPhotoUrl);
    currentPhotoUrl = null;
  }

  facePreviewImage = null;
  faceCutout = null;
  appState.faceTexture = getDefaultFaceTexture();
  mapFaceTexture.checked = false;
  mapFaceTexture.disabled = true;
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
    facePreviewImage = image;
    faceCutout = detectFaceCutout(image);
    appState.faceTexture = {
      enabled: true,
      mode: "cutout_overlay"
    };
    mapFaceTexture.checked = true;
    mapFaceTexture.disabled = false;
    const recommendation = recommendFromImage(image);
    recommendation.faceMorph = estimateFaceMorph(image, faceCutout);
    URL.revokeObjectURL(currentPhotoUrl);
    currentPhotoUrl = null;
    applyFaceRecommendation(recommendation);
  };
  image.onerror = () => {
    URL.revokeObjectURL(currentPhotoUrl);
    currentPhotoUrl = null;
    facePreviewImage = null;
    faceCutout = null;
    setFaceStatus("Could not read this image.");
    render();
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
  appState.faceMorph = recommendation.faceMorph ?? appState.faceMorph ?? getDefaultFaceMorph();
  appState.source = {
    kind: "face_recommendation",
    faceAnalysisJobId: recommendation.jobId
  };

  syncForm();
  renderFaceResult(recommendation);
  setFaceStatus("Recommendation applied with a temporary face texture on the avatar.");
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
    <span>Morph: ${formatFaceMorph(recommendation.faceMorph)}</span>
    <span>Face texture: ${appState.faceTexture?.enabled ? "mapped" : "off"}</span>
  `;
}

function getDefaultFaceMorph() {
  return {
    widthScale: 1,
    heightScale: 1,
    depth: 0.5,
    eyeOffsetY: 0,
    mouthOffsetY: 0
  };
}

function getDefaultFaceTexture() {
  return {
    enabled: false,
    mode: "cutout_overlay"
  };
}

function estimateFaceMorph(image, crop) {
  const faceRatio = crop.width / crop.height;
  const imageCenterX = image.width / 2;
  const imageCenterY = image.height / 2;
  const cropCenterX = crop.x + crop.width / 2;
  const cropCenterY = crop.y + crop.height / 2;
  const horizontalBias = (cropCenterX - imageCenterX) / image.width;
  const verticalBias = (cropCenterY - imageCenterY) / image.height;

  return {
    widthScale: clampNumber(0.9 + faceRatio * 0.18, 0.86, 1.16),
    heightScale: clampNumber(1.1 - faceRatio * 0.14, 0.9, 1.18),
    depth: clampNumber(0.5 + Math.abs(horizontalBias) * 1.8, 0.35, 0.85),
    eyeOffsetY: Math.round(clampNumber(verticalBias * 42, -10, 10)),
    mouthOffsetY: Math.round(clampNumber((0.08 - verticalBias) * 36, -8, 12))
  };
}

function clampNumber(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function formatFaceMorph(morph = getDefaultFaceMorph()) {
  return `w${morph.widthScale.toFixed(2)} h${morph.heightScale.toFixed(2)} d${morph.depth.toFixed(2)}`;
}

function drawFacePhotoReference() {
  if (!facePreviewImage) return;

  const { width } = previewCanvas;
  const frameX = width - 196;
  const frameY = 78;
  const frameSize = 132;
  const centerX = frameX + frameSize / 2;
  const centerY = frameY + frameSize / 2;

  ctx.save();
  ctx.fillStyle = "rgba(255, 255, 255, 0.88)";
  ctx.beginPath();
  ctx.roundRect(frameX - 18, frameY - 44, frameSize + 36, frameSize + 82, 28);
  ctx.fill();

  ctx.fillStyle = "rgba(31, 36, 35, 0.72)";
  ctx.font = "700 20px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText("face cutout", centerX, frameY - 16);

  ctx.beginPath();
  traceFaceContourPath(centerX, centerY, frameSize);
  ctx.clip();

  const crop = faceCutout ?? getCenteredSquareCrop(facePreviewImage);

  ctx.drawImage(
    facePreviewImage,
    crop.x,
    crop.y,
    crop.width,
    crop.height,
    frameX,
    frameY,
    frameSize,
    frameSize
  );

  ctx.restore();
  ctx.strokeStyle = "rgba(34, 124, 114, 0.8)";
  ctx.lineWidth = 5;
  ctx.beginPath();
  traceFaceContourPath(centerX, centerY, frameSize);
  ctx.stroke();
}

function drawMappedFaceTexture(centerX, y, width, height) {
  if (!facePreviewImage || !appState.faceTexture?.enabled) return;

  const crop = faceCutout ?? getCenteredSquareCrop(facePreviewImage);
  const textureWidth = width * 0.78;
  const textureHeight = height * 0.82;
  const textureX = centerX - textureWidth / 2;
  const textureY = y - textureHeight * 0.48;

  ctx.save();
  ctx.beginPath();
  traceFaceContourPath(centerX, y + height * 0.02, Math.max(width, height) * 0.86);
  ctx.clip();
  ctx.globalAlpha = 0.9;
  ctx.drawImage(
    facePreviewImage,
    crop.x,
    crop.y,
    crop.width,
    crop.height,
    textureX,
    textureY,
    textureWidth,
    textureHeight
  );
  ctx.globalAlpha = 1;
  ctx.fillStyle = "rgba(255, 255, 255, 0.12)";
  ctx.beginPath();
  ctx.ellipse(centerX - width * 0.16, y - height * 0.18, width * 0.2, height * 0.18, -0.35, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function traceFaceContourPath(centerX, centerY, size) {
  const top = centerY - size * 0.48;
  const left = centerX - size * 0.39;
  const right = centerX + size * 0.39;
  const chin = centerY + size * 0.48;

  ctx.moveTo(centerX, top);
  ctx.bezierCurveTo(right, top + size * 0.05, right + size * 0.12, centerY + size * 0.08, right - size * 0.02, centerY + size * 0.31);
  ctx.bezierCurveTo(centerX + size * 0.24, chin, centerX - size * 0.24, chin, left + size * 0.02, centerY + size * 0.31);
  ctx.bezierCurveTo(left - size * 0.12, centerY + size * 0.08, left, top + size * 0.05, centerX, top);
}

function getCenteredSquareCrop(image) {
  const size = Math.min(image.width, image.height);
  return {
    x: (image.width - size) / 2,
    y: (image.height - size) / 2,
    width: size,
    height: size
  };
}

function detectFaceCutout(image) {
  const sampleCanvas = document.createElement("canvas");
  const sampleWidth = 120;
  const sampleHeight = 120;
  sampleCanvas.width = sampleWidth;
  sampleCanvas.height = sampleHeight;

  const sampleContext = sampleCanvas.getContext("2d", { willReadFrequently: true });
  sampleContext.drawImage(image, 0, 0, sampleWidth, sampleHeight);
  const pixels = sampleContext.getImageData(0, 0, sampleWidth, sampleHeight).data;

  let minX = sampleWidth;
  let minY = sampleHeight;
  let maxX = 0;
  let maxY = 0;
  let count = 0;

  for (let y = Math.round(sampleHeight * 0.18); y < Math.round(sampleHeight * 0.86); y += 1) {
    for (let x = Math.round(sampleWidth * 0.18); x < Math.round(sampleWidth * 0.82); x += 1) {
      const index = (y * sampleWidth + x) * 4;
      const red = pixels[index];
      const green = pixels[index + 1];
      const blue = pixels[index + 2];
      const brightness = (red + green + blue) / 3;
      const warmth = red - blue;

      if (brightness > 45 && brightness < 235 && warmth > -18 && red > green * 0.82) {
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
        count += 1;
      }
    }
  }

  if (count < 80) return getCenteredSquareCrop(image);

  const scaleX = image.width / sampleWidth;
  const scaleY = image.height / sampleHeight;
  const centerX = ((minX + maxX) / 2) * scaleX;
  const centerY = ((minY + maxY) / 2) * scaleY;
  const width = Math.max((maxX - minX) * scaleX * 1.55, image.width * 0.24);
  const height = Math.max((maxY - minY) * scaleY * 1.55, image.height * 0.24);
  const size = Math.min(Math.max(width, height), Math.min(image.width, image.height));

  return {
    x: Math.max(0, Math.min(image.width - size, centerX - size / 2)),
    y: Math.max(0, Math.min(image.height - size, centerY - size / 2)),
    width: size,
    height: size
  };
}

function syncForm() {
  for (const name of Object.keys(partOptions)) {
    document.querySelector(`#${name}-select`).value = appState.parts[name];
  }

  document.querySelector("#skin-color").value = appState.colors.skin;
  document.querySelector("#hair-color").value = appState.colors.hair;
  mapFaceTexture.checked = Boolean(appState.faceTexture?.enabled && facePreviewImage);
  mapFaceTexture.disabled = !facePreviewImage;
}

function render() {
  drawAvatar();
  renderConfig();
  renderExportJob();
  renderAiCandidates();
}

function animateAvatar(timestamp) {
  if (!rotationStartedAt) rotationStartedAt = timestamp;
  currentTurn = ((timestamp - rotationStartedAt) / 9000) * Math.PI * 2;
  drawAvatar();
  window.requestAnimationFrame(animateAvatar);
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
getModelUrlButton.addEventListener("click", getAvatarModelUrl);
generateAiButton.addEventListener("click", generateAiCandidates);
aiCandidates.addEventListener("click", handleCandidateAction);
mapFaceTexture.addEventListener("change", () => {
  appState.faceTexture = {
    ...getDefaultFaceTexture(),
    ...appState.faceTexture,
    enabled: mapFaceTexture.checked
  };
  render();
});
analyzeFaceButton.addEventListener("click", analyzeFacePhoto);
clearFaceButton.addEventListener("click", clearFacePhoto);
render();
window.requestAnimationFrame(animateAvatar);
