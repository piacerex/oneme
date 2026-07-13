import * as THREE from "https://unpkg.com/three@0.160.0/build/three.module.js";
import {OrbitControls} from "https://unpkg.com/three@0.160.0/examples/jsm/controls/OrbitControls.js";
import {GLTFExporter} from "https://unpkg.com/three@0.160.0/examples/jsm/exporters/GLTFExporter.js";

const container = document.querySelector("#avatar-preview");

if (container) {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf0f1ed);
  const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 100);
  camera.position.set(0, 1.25, 5.4);
  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false});
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.replaceChildren(renderer.domElement);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.minDistance = 3.6;
  controls.maxDistance = 7.5;
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
    hair: new THREE.MeshStandardMaterial({color: 0x2f2118, roughness: 0.72}),
    top: new THREE.MeshStandardMaterial({color: 0x347f7b, roughness: 0.68}),
    bottom: new THREE.MeshStandardMaterial({color: 0x363d49, roughness: 0.7}),
    shoes: new THREE.MeshStandardMaterial({color: 0x232323, roughness: 0.6}),
    face: new THREE.MeshBasicMaterial({transparent: true, opacity: 0, depthWrite: false})
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

  const faceOverlay = new THREE.Mesh(new THREE.PlaneGeometry(0.66, 0.76), materials.face);
  faceOverlay.position.set(0, 1.78, 0.435);
  avatar.add(faceOverlay);

  const hair = new THREE.Mesh(
    new THREE.SphereGeometry(0.56, 32, 18, 0, Math.PI * 2, 0, Math.PI * 0.72),
    materials.hair
  );
  hair.position.y = 1.91;
  hair.scale.set(1, 0.92, 0.92);
  avatar.add(hair);

  avatar.add(createLimb(materials.top, -0.78, 0.35));
  avatar.add(createLimb(materials.top, 0.78, 0.35));
  avatar.add(createLimb(materials.skin, -0.88, -0.34, 0.18, 0.16));
  avatar.add(createLimb(materials.skin, 0.88, -0.34, 0.18, 0.16));
  avatar.add(createLimb(materials.bottom, -0.22, -1.02, 0.18, 0.8));
  avatar.add(createLimb(materials.bottom, 0.22, -1.02, 0.18, 0.8));
  avatar.add(createShoe(-0.22), createShoe(0.22));

  const eyes = new THREE.Group();
  eyes.position.set(0, 1.81, 0.43);
  eyes.add(createEye(-0.15), createEye(0.15));
  avatar.add(eyes);

  const mouth = new THREE.Mesh(
    new THREE.TorusGeometry(0.12, 0.012, 8, 28, Math.PI),
    new THREE.MeshBasicMaterial({color: 0x2a211d})
  );
  mouth.position.set(0, 1.64, 0.44);
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
  window.onemeThreePreview = {
    sync(config) {
      const colors = config?.colors || {};
      materials.skin.color.set(colors.skin || "#c98f6f");
      materials.hair.color.set(colors.hair || "#2f2118");
      materials.top.color.set(topPalette[config?.parts?.top] || "#347f7b");
      materials.bottom.color.set(bottomPalette[config?.parts?.bottom] || "#363d49");
      materials.shoes.color.set(shoePalette[config?.parts?.shoes] || "#232323");

      const morph = config?.faceMorph || {};
      avatar.userData.oneme = {config};
      head.scale.set(morph.widthScale || 1, morph.heightScale || 1.06, 0.82 + (morph.depth || 0.5) * 0.18);
      faceOverlay.scale.set(morph.widthScale || 1, morph.heightScale || 1.06, 1);
      eyes.position.y = 1.81 + (morph.eyeOffsetY || 0) / 120;
      mouth.position.y = 1.64 + (morph.mouthOffsetY || 0) / 120;
      materials.face.opacity = faceTexture ? 0.96 : 0;
    },
    setFaceImage(dataUrl) {
      faceDataUrl = dataUrl;
      const image = new Image();
      image.onload = () => {
        faceTexture?.dispose();
        faceTexture = new THREE.Texture(image);
        faceTexture.colorSpace = THREE.SRGBColorSpace;
        faceTexture.needsUpdate = true;
        materials.face.map = faceTexture;
        materials.face.opacity = 0.96;
        materials.face.needsUpdate = true;
      };
      image.src = dataUrl;
    },
    clearFaceImage() {
      faceTexture?.dispose();
      faceTexture = null;
      faceDataUrl = null;
      materials.face.map = null;
      materials.face.opacity = 0;
      materials.face.needsUpdate = true;
    },
    getFaceTextureDataUrl() {
      return faceDataUrl;
    },
    exportGlb(config, filename) {
      return new Promise((resolve, reject) => {
        const includeFaceTexture = config?.faceTexture?.exportConsent === true;
        const previousMap = materials.face.map;
        const previousOpacity = materials.face.opacity;

        const restoreFaceMaterial = () => {
          materials.face.map = previousMap;
          materials.face.opacity = previousOpacity;
          materials.face.needsUpdate = true;
        };

        if (!includeFaceTexture) {
          materials.face.map = null;
          materials.face.opacity = 0;
          materials.face.needsUpdate = true;
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
  window.addEventListener("resize", resize);
  renderer.setAnimationLoop(render);
  resize();

  function createLimb(material, x, y, radius = 0.17, length = 0.82) {
    const limb = new THREE.Mesh(new THREE.CapsuleGeometry(radius, length, 10, 16), material);
    limb.position.set(x, y, 0);
    limb.rotation.z = x < 0 ? -0.04 : 0.04;
    return limb;
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
    const rect = container.getBoundingClientRect();
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
