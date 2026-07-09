import * as THREE from "https://unpkg.com/three@0.160.0/build/three.module.js";

const container = document.querySelector("#three-preview");

if (container) {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf1eee7);

  const camera = new THREE.PerspectiveCamera(36, 3 / 4, 0.1, 100);
  camera.position.set(0, 1.45, 5.2);

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.append(renderer.domElement);

  const avatar = new THREE.Group();
  scene.add(avatar);

  const hemiLight = new THREE.HemisphereLight(0xffffff, 0x8f8a82, 2.2);
  scene.add(hemiLight);

  const keyLight = new THREE.DirectionalLight(0xffffff, 2.4);
  keyLight.position.set(2, 4, 4);
  scene.add(keyLight);

  const materials = {
    skin: new THREE.MeshStandardMaterial({ color: 0xc98f6f, roughness: 0.62 }),
    hair: new THREE.MeshStandardMaterial({ color: 0x2f2118, roughness: 0.72 }),
    top: new THREE.MeshStandardMaterial({ color: 0x347f7b, roughness: 0.68 }),
    bottom: new THREE.MeshStandardMaterial({ color: 0x363d49, roughness: 0.7 }),
    shoes: new THREE.MeshStandardMaterial({ color: 0x232323, roughness: 0.6 }),
    faceTexture: new THREE.MeshStandardMaterial({
      color: 0xffffff,
      roughness: 0.58,
      transparent: true,
      opacity: 0.0
    })
  };

  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.62, 1.1, 12, 24), materials.top);
  body.position.y = 0.5;
  body.scale.set(1.1, 1, 0.72);
  avatar.add(body);

  const neck = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.16, 8, 16), materials.skin);
  neck.position.y = 1.42;
  avatar.add(neck);

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.48, 32, 24), materials.skin);
  head.position.y = 1.9;
  head.scale.set(1, 1.06, 0.9);
  avatar.add(head);

  const faceOverlay = new THREE.Mesh(new THREE.CircleGeometry(0.33, 48), materials.faceTexture);
  faceOverlay.position.set(0, 1.9, 0.435);
  avatar.add(faceOverlay);

  const hair = new THREE.Mesh(new THREE.SphereGeometry(0.56, 32, 18, 0, Math.PI * 2, 0, Math.PI * 0.72), materials.hair);
  hair.position.y = 2.03;
  hair.scale.set(1.0, 0.92, 0.92);
  avatar.add(hair);

  const leftArm = createLimb(materials.top, -0.78, 0.54);
  const rightArm = createLimb(materials.top, 0.78, 0.54);
  avatar.add(leftArm, rightArm);

  const leftHand = createLimb(materials.skin, -0.88, -0.18, 0.18, 0.16);
  const rightHand = createLimb(materials.skin, 0.88, -0.18, 0.18, 0.16);
  avatar.add(leftHand, rightHand);

  const leftLeg = createLimb(materials.bottom, -0.22, -0.88, 0.18, 0.8);
  const rightLeg = createLimb(materials.bottom, 0.22, -0.88, 0.18, 0.8);
  avatar.add(leftLeg, rightLeg);

  const leftShoe = createShoe(-0.22);
  const rightShoe = createShoe(0.22);
  avatar.add(leftShoe, rightShoe);

  const eyes = new THREE.Group();
  eyes.position.y = 1.93;
  avatar.add(eyes);
  eyes.add(createEye(-0.15), createEye(0.15));

  const mouth = new THREE.Mesh(new THREE.TorusGeometry(0.12, 0.012, 8, 28, Math.PI), new THREE.MeshStandardMaterial({ color: 0x2a211d }));
  mouth.position.set(0, 1.75, 0.45);
  mouth.rotation.set(0, 0, Math.PI);
  avatar.add(mouth);

  const floor = new THREE.Mesh(
    new THREE.CircleGeometry(1.25, 48),
    new THREE.MeshBasicMaterial({ color: 0xcdd4cf, transparent: true, opacity: 0.8 })
  );
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -1.72;
  scene.add(floor);

  window.onemeThreePreview = {
    sync(config) {
      syncAvatar(config);
    }
  };

  resize();
  window.addEventListener("resize", resize);
  renderer.setAnimationLoop(render);

  function createLimb(material, x, y, radius = 0.17, length = 0.82) {
    const limb = new THREE.Mesh(new THREE.CapsuleGeometry(radius, length, 10, 16), material);
    limb.position.set(x, y, 0);
    limb.rotation.z = x < 0 ? -0.04 : 0.04;
    return limb;
  }

  function createShoe(x) {
    const shoe = new THREE.Mesh(new THREE.CapsuleGeometry(0.16, 0.18, 8, 16), materials.shoes);
    shoe.position.set(x, -1.42, 0.08);
    shoe.scale.set(1.45, 0.48, 0.8);
    shoe.rotation.z = Math.PI / 2;
    return shoe;
  }

  function createEye(x) {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.035, 12, 8), new THREE.MeshBasicMaterial({ color: 0x1f2423 }));
    eye.position.set(x, 0, 0.44);
    return eye;
  }

  function syncAvatar(config) {
    if (!config) return;

    materials.skin.color.set(config.colors?.skin ?? "#c98f6f");
    materials.hair.color.set(config.colors?.hair ?? "#2f2118");
    materials.top.color.set(topPalette[config.parts?.top] ?? "#347f7b");
    materials.bottom.color.set(bottomPalette[config.parts?.bottom] ?? "#363d49");
    materials.shoes.color.set(shoePalette[config.parts?.shoes] ?? "#232323");

    const morph = config.faceMorph ?? {};
    head.scale.set(morph.widthScale ?? 1, morph.heightScale ?? 1.06, 0.82 + (morph.depth ?? 0.5) * 0.18);
    faceOverlay.scale.set((morph.widthScale ?? 1) * 1.0, (morph.heightScale ?? 1) * 1.06, 1);
    eyes.position.y = 1.93 - 1.9 + (morph.eyeOffsetY ?? 0) / 120;
    mouth.position.y = 1.75 + (morph.mouthOffsetY ?? 0) / 120;
    materials.faceTexture.opacity = config.faceTexture?.enabled ? 0.28 : 0.0;
  }

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
}
