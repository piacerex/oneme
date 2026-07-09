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
const ctx = previewCanvas.getContext("2d");

function renderConfig() {
  configOutput.textContent = JSON.stringify(appState, null, 2);
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

function render() {
  drawAvatar();
  renderConfig();
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
render();
