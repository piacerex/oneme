export class OnemeClient {
  constructor(options = {}) {
    this.storage = options.storage ?? globalThis.localStorage;
    this.apiBaseUrl = options.apiBaseUrl?.replace(/\/$/, "") ?? "";
    this.fetch = options.fetch ?? globalThis.fetch?.bind(globalThis);
    this.avatarPrefix = options.avatarPrefix ?? "oneme.avatars";
    this.exportJobsKey = options.exportJobsKey ?? "oneme.exportJobs";
    this.exportCacheKey = options.exportCacheKey ?? "oneme.exportCache";
  }

  getLatestAvatar() {
    return this.#getSavedAvatars()[0] ?? null;
  }

  getAvatar(avatarId) {
    return this.#getSavedAvatars().find((avatar) => avatar.avatarId === avatarId) ?? null;
  }

  listExportJobs() {
    return this.#getJsonArray(this.exportJobsKey);
  }

  getModel(avatarId) {
    const job = this.listExportJobs().find(
      (item) => item.status === "succeeded" && item.avatarConfig?.avatarId === avatarId
    );
    if (!job) return null;

    const cache = this.#getJsonObject(this.exportCacheKey)[job.cacheKey];
    return {
      avatarId,
      format: "glb",
      modelUrl: job.modelUrl ?? job.modelResponse?.modelUrl ?? "",
      exportJobId: job.id,
      cacheHit: Boolean(cache)
    };
  }

  async fetchAvatar(avatarId) {
    return this.#requestJson(`/api/avatars/${encodeURIComponent(avatarId)}`);
  }

  async fetchModel(avatarId, options = {}) {
    const format = options.format ?? "glb";
    return this.#requestJson(
      `/api/avatars/${encodeURIComponent(avatarId)}/model?format=${encodeURIComponent(format)}`
    );
  }

  async fetchPublicAvatar(avatarId) {
    return this.#requestJson(`/api/avatars/${encodeURIComponent(avatarId)}/public`);
  }

  async fetchParts() {
    const response = await this.#requestJson("/api/parts");
    return response.parts ?? [];
  }

  async createFaceAnalysisJob(payload) {
    return this.#requestJson("/api/face-analysis-jobs", {
      method: "POST",
      body: payload
    });
  }

  async fetchFaceAnalysisJob(jobId) {
    return this.#requestJson(`/api/face-analysis-jobs/${encodeURIComponent(jobId)}`);
  }

  async createAvatarFromFaceAnalysis(payload) {
    return this.#requestJson("/api/avatars/from-face-analysis", {
      method: "POST",
      body: payload
    });
  }

  async createAiGenerationJob(payload) {
    return this.#requestJson("/api/ai_generation_jobs", {
      method: "POST",
      body: payload
    });
  }

  async fetchAiGenerationJob(jobId) {
    return this.#requestJson(`/api/ai_generation_jobs/${encodeURIComponent(jobId)}`);
  }

  async createAvatarFromAiCandidate(payload) {
    return this.#requestJson("/api/avatars/from_ai_candidate", {
      method: "POST",
      body: payload
    });
  }

  async createRecommendationFeedback(payload) {
    return this.#requestJson("/api/recommendation_feedback", {
      method: "POST",
      body: payload
    });
  }

  async listRecommendationFeedback() {
    const response = await this.#requestJson("/api/recommendation_feedback");
    return response.recommendationFeedback ?? [];
  }

  async createExportJob(payload, options = {}) {
    const path = options.format === "vrm" ? "/api/vrm_export_jobs" : "/api/export_jobs";
    return this.#requestJson(path, {
      method: "POST",
      body: payload
    });
  }

  async fetchExportJob(jobId, options = {}) {
    const collection = options.format === "vrm" ? "vrm_export_jobs" : "export_jobs";
    return this.#requestJson(`/api/${collection}/${encodeURIComponent(jobId)}`);
  }

  async createWidgetApp(payload) {
    return this.#requestJson("/api/apps", {
      method: "POST",
      body: payload
    });
  }

  async createAppApiKey(appId, payload) {
    return this.#requestJson(`/api/apps/${encodeURIComponent(appId)}/api_keys`, {
      method: "POST",
      body: payload
    });
  }

  async revokeAppApiKey(appId, apiKey) {
    return this.#requestJson(`/api/apps/${encodeURIComponent(appId)}/api_keys/${encodeURIComponent(apiKey)}`, {
      method: "DELETE"
    });
  }

  async fetchAdminDashboard() {
    return this.#requestJson("/api/admin/dashboard");
  }

  async fetchBillingUsage(teamId) {
    return this.#requestJson(`/api/billing_usage/${encodeURIComponent(teamId)}`);
  }

  async createStatusPageUpdate(payload) {
    return this.#requestJson("/api/status_page_updates", {
      method: "POST",
      body: payload
    });
  }

  async #requestJson(path, options = {}) {
    if (!this.apiBaseUrl) {
      throw new Error("OnemeClient requires apiBaseUrl for API requests");
    }
    if (!this.fetch) {
      throw new Error("OnemeClient requires a fetch implementation");
    }

    const headers = {
      accept: "application/json"
    };
    if (options.body !== undefined) {
      headers["content-type"] = "application/json";
    }

    const response = await this.fetch(`${this.apiBaseUrl}${path}`, {
      method: options.method ?? "GET",
      headers: {
        ...headers
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body)
    });

    if (!response.ok) {
      throw new Error(`oneme API request failed: ${response.status}`);
    }

    return response.json();
  }

  #getSavedAvatars() {
    return this.#getJsonArray(this.avatarPrefix);
  }

  #getJsonArray(key) {
    const raw = this.storage?.getItem(key);
    if (!raw) return [];

    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  #getJsonObject(key) {
    const raw = this.storage?.getItem(key);
    if (!raw) return {};

    try {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
    } catch {
      return {};
    }
  }
}

export function createThreeAvatar(config, THREE) {
  const group = new THREE.Group();
  const materials = createMaterials(config, THREE);

  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.62, 1.1, 12, 24), materials.top);
  body.position.y = 0.5;
  body.scale.set(1.1, 1, 0.72);
  group.add(body);

  const neck = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.16, 8, 16), materials.skin);
  neck.position.y = 1.42;
  group.add(neck);

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.48, 32, 24), materials.skin);
  head.position.y = 1.9;
  const morph = config.faceMorph ?? {};
  head.scale.set(morph.widthScale ?? 1, morph.heightScale ?? 1.06, 0.82 + (morph.depth ?? 0.5) * 0.18);
  group.add(head);

  const hair = new THREE.Mesh(
    new THREE.SphereGeometry(0.56, 32, 18, 0, Math.PI * 2, 0, Math.PI * 0.72),
    materials.hair
  );
  hair.position.y = 2.03;
  group.add(hair);

  group.add(createLimb(THREE, materials.top, -0.78, 0.54));
  group.add(createLimb(THREE, materials.top, 0.78, 0.54));
  group.add(createLimb(THREE, materials.skin, -0.88, -0.18, 0.18, 0.16));
  group.add(createLimb(THREE, materials.skin, 0.88, -0.18, 0.18, 0.16));
  group.add(createLimb(THREE, materials.bottom, -0.22, -0.88, 0.18, 0.8));
  group.add(createLimb(THREE, materials.bottom, 0.22, -0.88, 0.18, 0.8));

  return group;
}

export function mountThreeAvatar(container, config, options = {}) {
  const THREE = options.THREE;
  if (!THREE) throw new Error("mountThreeAvatar requires options.THREE");

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(options.background ?? 0xf1eee7);

  const camera = new THREE.PerspectiveCamera(36, 3 / 4, 0.1, 100);
  camera.position.set(0, 1.45, 5.2);

  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio ?? 1, 2));
  container.append(renderer.domElement);

  const avatar = createThreeAvatar(config, THREE);
  scene.add(avatar);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x8f8a82, 2.2));

  const keyLight = new THREE.DirectionalLight(0xffffff, 2.4);
  keyLight.position.set(2, 4, 4);
  scene.add(keyLight);

  function resize() {
    const rect = container.getBoundingClientRect();
    const width = Math.max(1, rect.width);
    const height = Math.max(1, rect.height);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
  }

  function render(time) {
    avatar.rotation.y = time / 3600;
    renderer.render(scene, camera);
  }

  resize();
  globalThis.addEventListener("resize", resize);
  renderer.setAnimationLoop(render);

  return {
    scene,
    camera,
    renderer,
    avatar,
    dispose() {
      renderer.setAnimationLoop(null);
      globalThis.removeEventListener("resize", resize);
      renderer.dispose();
      renderer.domElement.remove();
    }
  };
}

function createMaterials(config, THREE) {
  return {
    skin: new THREE.MeshStandardMaterial({ color: config.colors?.skin ?? "#c98f6f", roughness: 0.62 }),
    hair: new THREE.MeshStandardMaterial({ color: config.colors?.hair ?? "#2f2118", roughness: 0.72 }),
    top: new THREE.MeshStandardMaterial({ color: topPalette[config.parts?.top] ?? "#347f7b", roughness: 0.68 }),
    bottom: new THREE.MeshStandardMaterial({ color: bottomPalette[config.parts?.bottom] ?? "#363d49", roughness: 0.7 })
  };
}

function createLimb(THREE, material, x, y, radius = 0.17, length = 0.82) {
  const limb = new THREE.Mesh(new THREE.CapsuleGeometry(radius, length, 10, 16), material);
  limb.position.set(x, y, 0);
  return limb;
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
