window.onemeWidgetApps = [
  {
    id: "demo-app",
    name: "Demo Host",
    apiKeys: ["demo-key"],
    allowedOrigins: ["*"],
    theme: "mint",
    allowedParts: {
      hair: ["hair.short_01", "hair.medium_01", "hair.long_01"],
      top: ["top.basic_01", "top.hoodie_01"],
      accessory: ["accessory.none", "accessory.glasses_round_01"]
    }
  },
  {
    id: "mono-app",
    name: "Mono Partner",
    apiKeys: ["mono-key"],
    allowedOrigins: ["*"],
    theme: "mono",
    allowedParts: {
      hair: ["hair.short_01", "hair.none"],
      top: ["top.jacket_01"],
      accessory: ["accessory.none"]
    }
  }
];
