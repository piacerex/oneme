const params = new URLSearchParams(window.location.search);
const appId = params.get("app_id") ?? "";
const apiKey = params.get("api_key") ?? "";
const requestedTheme = params.get("theme");
const resumeAvatarId = params.get("resume");
const apiBaseUrl = params.get("api")?.replace(/\/$/, "") ?? "";

const apps = window.onemeWidgetApps ?? [];
const app = apps.find((item) => item.id === appId && item.apiKeys.includes(apiKey));
const card = document.querySelector("#widget-card");
const appName = document.querySelector("#app-name");
const form = document.querySelector("#widget-form");
const saveButton = document.querySelector("#widget-save");
const statusText = document.querySelector("#widget-status");
const canvas = document.querySelector("#widget-preview");
const ctx = canvas.getContext("2d");

const options = {
  hair: [
    ["hair.short_01", "Short"],
    ["hair.medium_01", "Medium"],
    ["hair.long_01", "Long"],
    ["hair.none", "Bald"]
  ],
  top: [
    ["top.basic_01", "Basic Tee"],
    ["top.hoodie_01", "Hoodie"],
    ["top.jacket_01", "Jacket"]
  ],
  accessory: [
    ["accessory.none", "None"],
    ["accessory.glasses_round_01", "Round Glasses"],
    ["accessory.hat_cap_01", "Cap"]
  ]
};

let state = {
  version: "0.1.0",
  avatarId: resumeAvatarId || `widget-${Date.now()}`,
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

if (!app) {
  fail("Invalid app credentials");
} else {
  boot();
}

async function boot() {
  card.dataset.theme = requestedTheme || app.theme;
  appName.textContent = app.name;
  await loadApiOptions();
  populate("hair");
  populate("top");
  populate("accessory");
  form.addEventListener("input", updateState);
  saveButton.addEventListener("click", saveAvatar);
  statusText.textContent = "Ready";
  render();
  post("oneme.widget.ready", { appId: app.id });
}

async function loadApiOptions() {
  if (!apiBaseUrl) return;

  try {
    const response = await fetchJson("/api/parts");
    const grouped = groupParts(response.parts ?? []);
    for (const name of Object.keys(options)) {
      if (grouped[name]?.length) options[name] = grouped[name];
    }
  } catch (error) {
    statusText.textContent = "Using local widget parts";
    post("oneme.widget.warning", {
      appId: app.id,
      warning: error instanceof Error ? error.message : String(error)
    });
  }
}

function groupParts(parts) {
  return parts.reduce((grouped, part) => {
    if (!options[part.category]) return grouped;
    grouped[part.category] = grouped[part.category] ?? [];
    grouped[part.category].push([part.id, part.label ?? part.id]);
    return grouped;
  }, {});
}

function fail(error) {
  statusText.textContent = error;
  saveButton.disabled = true;
  form.querySelectorAll("select,input").forEach((input) => {
    input.disabled = true;
  });
  post("oneme.widget.error", { appId, error });
}

function populate(name) {
  const select = document.querySelector(`#widget-${name}`);
  const allowed = app.allowedParts[name];
  const filtered = allowed ? options[name].filter(([id]) => allowed.includes(id)) : options[name];

  for (const [id, label] of filtered) {
    const option = document.createElement("option");
    option.value = id;
    option.textContent = label;
    select.append(option);
  }

  state.parts[name] = filtered[0]?.[0] ?? state.parts[name];
  select.value = state.parts[name];
}

function updateState(event) {
  const target = event.target;
  if (target.name === "skin") {
    state.colors.skin = target.value;
  } else if (target.name in state.parts) {
    state.parts[target.name] = target.value;
  }
  render();
}

async function saveAvatar() {
  state = {
    ...state,
    avatarId: `widget-${Date.now()}`
  };
  if (apiBaseUrl) {
    state = await createRemoteAvatar(state);
  } else {
    window.localStorage.setItem(`oneme.widget.${state.avatarId}`, JSON.stringify(state));
  }
  statusText.textContent = `Saved ${state.avatarId}`;
  post("oneme.avatar.saved", {
    appId: app.id,
    avatarId: state.avatarId,
    config: state
  });
}

async function createRemoteAvatar(config) {
  try {
    return await fetchJson("/api/avatars", {
      method: "POST",
      body: JSON.stringify({ avatarConfig: config })
    });
  } catch (error) {
    statusText.textContent = "Remote save failed";
    post("oneme.widget.error", {
      appId: app.id,
      error: error instanceof Error ? error.message : String(error)
    });
    throw error;
  }
}

async function fetchJson(path, options = {}) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    ...options,
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      ...options.headers
    }
  });
  if (!response.ok) throw new Error(`API request failed: ${response.status}`);
  return response.json();
}

function post(type, payload) {
  window.parent.postMessage(
    {
      type,
      ...payload
    },
    "*"
  );
}

function render() {
  const width = canvas.width;
  const height = canvas.height;
  ctx.clearRect(0, 0, width, height);

  const background = ctx.createLinearGradient(0, 0, width, height);
  background.addColorStop(0, "#f7f1e8");
  background.addColorStop(1, "#dce8e4");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, width, height);

  const centerX = width / 2;
  ctx.fillStyle = "rgba(0, 0, 0, 0.13)";
  ctx.beginPath();
  ctx.ellipse(centerX, 380, 86, 18, 0, 0, Math.PI * 2);
  ctx.fill();

  drawCapsule(centerX - 28, 270, 24, 98, "#363d49");
  drawCapsule(centerX + 4, 270, 24, 98, "#363d49");
  drawCapsule(centerX - 40, 360, 42, 18, "#232323");
  drawCapsule(centerX - 2, 360, 42, 18, "#232323");
  drawCapsule(centerX - 58, 165, 116, 132, topColor());
  drawCapsule(centerX - 82, 178, 28, 110, topColor());
  drawCapsule(centerX + 54, 178, 28, 110, topColor());
  drawCapsule(centerX - 85, 282, 26, 34, state.colors.skin);
  drawCapsule(centerX + 59, 282, 26, 34, state.colors.skin);

  drawHair(centerX, 96);
  drawCapsule(centerX - 22, 143, 44, 42, state.colors.skin);
  ctx.fillStyle = state.colors.skin;
  ctx.beginPath();
  ctx.ellipse(centerX, 108, 38, 44, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#25211d";
  ctx.beginPath();
  ctx.ellipse(centerX - 14, 104, 4, 6, 0, 0, Math.PI * 2);
  ctx.ellipse(centerX + 14, 104, 4, 6, 0, 0, Math.PI * 2);
  ctx.fill();
}

function drawCapsule(x, y, width, height, color) {
  const radius = width / 2;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.roundRect(x, y, width, height, radius);
  ctx.fill();
}

function drawHair(centerX, y) {
  if (state.parts.hair === "hair.none") return;
  ctx.fillStyle = state.colors.hair;
  ctx.beginPath();
  if (state.parts.hair === "hair.long_01") {
    ctx.roundRect(centerX - 48, y - 30, 96, 104, 36);
  } else if (state.parts.hair === "hair.medium_01") {
    ctx.roundRect(centerX - 46, y - 28, 92, 76, 34);
  } else {
    ctx.roundRect(centerX - 43, y - 30, 86, 58, 30);
  }
  ctx.fill();
}

function topColor() {
  return {
    "top.basic_01": "#347f7b",
    "top.hoodie_01": "#6f4f8f",
    "top.jacket_01": "#2f3f54"
  }[state.parts.top] ?? "#347f7b";
}
