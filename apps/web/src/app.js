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

const configOutput = document.querySelector("#config-output");

function renderConfig() {
  configOutput.textContent = JSON.stringify(appState, null, 2);
}

renderConfig();
