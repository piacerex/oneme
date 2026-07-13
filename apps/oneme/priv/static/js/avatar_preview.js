import * as THREE from "https://unpkg.com/three@0.160.0/build/three.module.js";
import {OrbitControls} from "https://unpkg.com/three@0.160.0/examples/jsm/controls/OrbitControls.js";
import {GLTFExporter} from "https://unpkg.com/three@0.160.0/examples/jsm/exporters/GLTFExporter.js";

const container = document.querySelector("#avatar-preview");

if (container) {
  let previewContainer = container;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf0f1ed);
  const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 100);
  camera.position.set(0, 0.28, 7.2);
  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false});
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.replaceChildren(renderer.domElement);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 3.6;
  controls.maxDistance = 10;
  controls.minPolarAngle = Math.PI * 0.28;
  controls.maxPolarAngle = Math.PI * 0.7;
  controls.target.set(0, 0.25, 0);
  controls.update();

  const avatar = new THREE.Group();
  scene.add(avatar);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x7b817c, 2.3));
  const keyLight = new THREE.DirectionalLight(0xffffff, 2.4);
  keyLight.position.set(2, 4, 4);
  scene.add(keyLight);

  const materials = {
    skin: new THREE.MeshStandardMaterial({color: 0xc98f6f, roughness: 0.62}),
    top: new THREE.MeshStandardMaterial({color: 0x347f7b, roughness: 0.68}),
    bottom: new THREE.MeshStandardMaterial({color: 0x363d49, roughness: 0.7}),
    shoes: new THREE.MeshStandardMaterial({color: 0x232323, roughness: 0.6}),
    faceWrap: new THREE.MeshStandardMaterial({
      color: 0xffffff,
      roughness: 0.68,
      transparent: true,
      alphaTest: 0.01,
      depthWrite: false
    }),
    profileWrap: new THREE.MeshStandardMaterial({
      color: 0xffffff,
      roughness: 0.74,
      transparent: true,
      alphaTest: 0.01,
      depthWrite: false
    })
  };

  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.62, 1.1, 12, 24), materials.top);
  body.position.y = 0.35;
  body.scale.set(1.1, 1, 0.72);
  avatar.add(body);

  const neck = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.16, 8, 16), materials.skin);
  neck.position.y = 1.28;
  avatar.add(neck);

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.48, 32, 24), materials.skin);
  head.position.y = 1.78;
  head.scale.set(1, 1.06, 0.9);
  avatar.add(head);

  // Map the calibrated photo to the front hemisphere only. The base head stays
  // visible at the sides and back, so the square source image cannot wrap
  // eyes, nose, or mouth around the avatar.
  const faceWrap = new THREE.Mesh(
    new THREE.SphereGeometry(0.49, 64, 32, 0, Math.PI, 0, Math.PI),
    materials.faceWrap
  );
  faceWrap.position.y = 1.78;
  faceWrap.visible = false;
  avatar.add(faceWrap);

  const profileWrap = new THREE.Mesh(
    new THREE.SphereGeometry(0.488, 64, 32, Math.PI, Math.PI, 0, Math.PI),
    materials.profileWrap
  );
  profileWrap.position.y = 1.78;
  profileWrap.visible = false;
  avatar.add(profileWrap);

  avatar.add(createLimb(materials.top, -0.78, 0.35));
  avatar.add(createLimb(materials.top, 0.78, 0.35));
  avatar.add(createLimb(materials.skin, -0.88, -0.34, 0.18, 0.16));
  avatar.add(createLimb(materials.skin, 0.88, -0.34, 0.18, 0.16));
  avatar.add(createLimb(materials.bottom, -0.22, -1.02, 0.18, 0.8));
  avatar.add(createLimb(materials.bottom, 0.22, -1.02, 0.18, 0.8));
  avatar.add(createShoe(-0.22), createShoe(0.22));

  const eyes = new THREE.Group();
  eyes.position.set(0, 1.81, 0.46);
  eyes.add(createEye(-0.15), createEye(0.15));
  avatar.add(eyes);

  const mouth = new THREE.Mesh(
    new THREE.TorusGeometry(0.12, 0.012, 8, 28, Math.PI),
    new THREE.MeshBasicMaterial({color: 0x2a211d})
  );
  mouth.position.set(0, 1.64, 0.46);
  mouth.rotation.set(0, 0, Math.PI);
  avatar.add(mouth);

  const floor = new THREE.Mesh(
    new THREE.CircleGeometry(1.25, 48),
    new THREE.MeshBasicMaterial({color: 0xc8d0ca, transparent: true, opacity: 0.78})
  );
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -1.86;
  scene.add(floor);

  let faceTexture = null;
  let faceDataUrl = null;
  let faceCalibration = null;
  let profileTexture = null;
  let profileDataUrl = null;
  window.onemeThreePreview = {
    mount(nextContainer) {
      if (!(nextContainer instanceof HTMLElement)) return;

      previewContainer = nextContainer;
      if (renderer.domElement.parentElement !== previewContainer) {
        previewContainer.replaceChildren(renderer.domElement);
      }
      resize();
    },
    sync(config) {
      const colors = config?.colors || {};
      materials.skin.color.set(colors.skin || "#c98f6f");
      materials.top.color.set(topPalette[config?.parts?.top] || "#347f7b");
      materials.bottom.color.set(bottomPalette[config?.parts?.bottom] || "#363d49");
      materials.shoes.color.set(shoePalette[config?.parts?.shoes] || "#232323");

      const morph = config?.faceMorph || {};
      avatar.userData.oneme = {config};
      const headScale = {
        x: morph.widthScale || 1,
        y: morph.heightScale || 1.06,
        z: 0.82 + (morph.depth || 0.5) * 0.18
      };
      head.scale.set(headScale.x, headScale.y, headScale.z);
      faceWrap.scale.set(headScale.x * 1.012, headScale.y * 1.012, headScale.z * 1.012);
      profileWrap.scale.set(headScale.x * 1.008, headScale.y * 1.008, headScale.z * 1.008);
      eyes.position.y = 1.81 + (morph.eyeOffsetY || 0) / 120;
      mouth.position.y = 1.64 + (morph.mouthOffsetY || 0) / 120;
      applyFeatureMapping(config?.faceAnalysis?.calibration || faceCalibration);
      faceWrap.visible = Boolean(faceTexture);
    },
    setFaceImage(dataUrl, calibration) {
      faceDataUrl = dataUrl;
      faceCalibration = calibration || null;
      applyFeatureMapping(faceCalibration);
      const image = new Image();
      image.onload = () => {
        faceTexture?.dispose();
        faceTexture = new THREE.Texture(image);
        faceTexture.colorSpace = THREE.SRGBColorSpace;
        faceTexture.needsUpdate = true;
        materials.faceWrap.map = faceTexture;
        materials.faceWrap.opacity = 1;
        materials.faceWrap.needsUpdate = true;
        faceWrap.visible = true;
      };
      image.src = dataUrl;
    },
    setFaceCompletion(dataUrl) {
      profileDataUrl = dataUrl;
      const image = new Image();
      image.onload = () => {
        profileTexture?.dispose();
        profileTexture = new THREE.Texture(image);
        profileTexture.colorSpace = THREE.SRGBColorSpace;
        profileTexture.needsUpdate = true;
        materials.profileWrap.map = profileTexture;
        materials.profileWrap.opacity = 1;
        materials.profileWrap.needsUpdate = true;
        profileWrap.visible = true;
      };
      image.src = dataUrl;
    },
    clearFaceImage() {
      faceTexture?.dispose();
      faceTexture = null;
      faceDataUrl = null;
      faceCalibration = null;
      profileTexture?.dispose();
      profileTexture = null;
      profileDataUrl = null;
      materials.faceWrap.map = null;
      materials.faceWrap.opacity = 1;
      materials.faceWrap.needsUpdate = true;
      materials.profileWrap.map = null;
      materials.profileWrap.opacity = 1;
      materials.profileWrap.needsUpdate = true;
      faceWrap.visible = false;
      profileWrap.visible = false;
    },
    getFaceTextureDataUrl() {
      return faceDataUrl;
    },
    getFaceCalibration() {
      return faceCalibration;
    },
    getFaceCompletionDataUrl() {
      return profileDataUrl;
    },
    exportGlb(config, filename) {
      return new Promise((resolve, reject) => {
        const includeFaceTexture = config?.faceTexture?.exportConsent === true;
        const previousVisible = faceWrap.visible;
        const previousProfileVisible = profileWrap.visible;

        const restoreFaceMaterial = () => {
          faceWrap.visible = previousVisible;
          profileWrap.visible = previousProfileVisible;
        };

        if (!includeFaceTexture) {
          faceWrap.visible = false;
          profileWrap.visible = false;
        }

        new GLTFExporter().parse(
          avatar,
          result => {
            restoreFaceMaterial();
            const blob = new Blob([result], {type: "model/gltf-binary"});
            const url = URL.createObjectURL(blob);
            const link = document.createElement("a");
            link.href = url;
            link.download = filename || "oneme-avatar.glb";
            link.click();
            URL.revokeObjectURL(url);
            resolve({bytes: blob.size, includesFaceTexture: includeFaceTexture});
          },
          error => {
            restoreFaceMaterial();
            reject(error);
          },
          {binary: true, includeCustomExtensions: true}
        );
      });
    }
  };

  window.addEventListener("oneme:avatar-config", event => window.onemeThreePreview.sync(event.detail));
  if (window.onemeAvatarConfig) window.onemeThreePreview.sync(window.onemeAvatarConfig);
  window.dispatchEvent(new CustomEvent("oneme:preview-ready"));
  window.addEventListener("resize", resize);
  renderer.setAnimationLoop(render);
  resize();

  function createLimb(material, x, y, radius = 0.17, length = 0.82) {
    const limb = new THREE.Mesh(new THREE.CapsuleGeometry(radius, length, 10, 16), material);
    limb.position.set(x, y, 0);
    limb.rotation.z = x < 0 ? -0.04 : 0.04;
    return limb;
  }

  function applyFeatureMapping(calibration) {
    const mapped = calibration?.mappedLandmarks;
    const leftEye = mapped?.leftEye;
    const rightEye = mapped?.rightEye;
    const mouthPoint = mapped?.mouth;

    if (leftEye && rightEye) {
      const eyeCenterX = (leftEye.x + rightEye.x) / 2;
      const eyeCenterY = (leftEye.y + rightEye.y) / 2;
      eyes.position.x = ((eyeCenterX - 256) / 512) * 0.98;
      eyes.position.y = 1.78 + (0.5 - eyeCenterY / 512) * (0.49 * 1.06);
      eyes.scale.x = clamp(
        Math.hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y) / 154,
        0.82,
        1.2
      );
    } else {
      eyes.position.x = 0;
      eyes.position.y = 1.81;
      eyes.scale.x = 1;
    }

    if (mouthPoint) {
      mouth.position.x = ((mouthPoint.x - 256) / 512) * 0.98;
      mouth.position.y = 1.78 + (0.5 - mouthPoint.y / 512) * (0.49 * 1.06);
    } else {
      mouth.position.x = 0;
      mouth.position.y = 1.64;
    }
  }

  function createShoe(x) {
    const shoe = new THREE.Mesh(new THREE.CapsuleGeometry(0.16, 0.18, 8, 16), materials.shoes);
    shoe.position.set(x, -1.56, 0.08);
    shoe.scale.set(1.45, 0.48, 0.8);
    shoe.rotation.z = Math.PI / 2;
    return shoe;
  }

  function createEye(x) {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.035, 12, 8), new THREE.MeshBasicMaterial({color: 0x1f2423}));
    eye.position.set(x, 0, 0);
    return eye;
  }

  function resize() {
    const rect = previewContainer.getBoundingClientRect();
    const width = Math.max(1, rect.width);
    const height = Math.max(1, rect.height);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
  }

  function render(time) {
    avatar.rotation.y = time / 3600;
    controls.update();
    renderer.render(scene, camera);
  }

  const topPalette = {"top.basic_01": "#347f7b", "top.hoodie_01": "#6f4f8f", "top.jacket_01": "#2f3f54"};
  const bottomPalette = {"bottom.basic_01": "#363d49", "bottom.tapered_01": "#5f665f", "bottom.skirt_01": "#7b4c58"};
  const shoePalette = {"shoes.basic_01": "#232323", "shoes.sneaker_01": "#f4f0ea", "shoes.boot_01": "#4a3026"};
}
