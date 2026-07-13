function bootPreview() {
  const container = document.querySelector("#avatar-preview");

  if (!container) return;

  import("/js/avatar_preview.js").catch(error => {
    console.error("oneme 3D preview failed to initialize", error);
    const message = document.createElement("div");
    message.className = "preview-error";
    message.setAttribute("role", "alert");
    message.textContent = "3Dプレビューを読み込めませんでした。ページを再読み込みしてください。";
    container.replaceChildren(message);
    window.dispatchEvent(new CustomEvent("oneme:preview-error", {detail: error}));
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootPreview, {once: true});
} else {
  bootPreview();
}
