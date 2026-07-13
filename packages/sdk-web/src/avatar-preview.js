const DEFAULT_CONFIG = {
  colors: {skin: "#c98f6f", hair: "#2f2118"},
  faceMorph: {widthScale: 1, heightScale: 1.06, depth: 0.5},
  parts: {top: "top.basic_01", bottom: "bottom.basic_01", shoes: "shoes.basic_01"}
}

const TOP_COLORS = {
  "top.basic_01": "#347f7b",
  "top.hoodie_01": "#6f4f8f",
  "top.jacket_01": "#2f3f54"
}

const BOTTOM_COLORS = {
  "bottom.basic_01": "#363d49",
  "bottom.tapered_01": "#5f665f",
  "bottom.skirt_01": "#7b4c58"
}

const SHOE_COLORS = {
  "shoes.basic_01": "#232323",
  "shoes.sneaker_01": "#f4f0ea",
  "shoes.boot_01": "#4a3026"
}

export function mountAvatarPreview(container, {THREE, config = {}, autoRotate = true} = {}) {
  if (!container || !THREE) throw new Error("mountAvatarPreview requires a container and THREE")

  const scene = new THREE.Scene()
  scene.background = new THREE.Color(0xf0f1ed)
  const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 100)
  camera.position.set(0, 1.25, 5.4)
  const renderer = new THREE.WebGLRenderer({antialias: true, alpha: false})
  renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio || 1, 2))
  container.replaceChildren(renderer.domElement)

  const group = new THREE.Group()
  scene.add(group)
  scene.add(new THREE.HemisphereLight(0xffffff, 0x7b817c, 2.3))
  const keyLight = new THREE.DirectionalLight(0xffffff, 2.4)
  keyLight.position.set(2, 4, 4)
  scene.add(keyLight)

  const materials = {
    skin: new THREE.MeshStandardMaterial({color: 0xc98f6f, roughness: 0.62}),
    hair: new THREE.MeshStandardMaterial({color: 0x2f2118, roughness: 0.72}),
    top: new THREE.MeshStandardMaterial({color: 0x347f7b, roughness: 0.68}),
    bottom: new THREE.MeshStandardMaterial({color: 0x363d49, roughness: 0.7}),
    shoes: new THREE.MeshStandardMaterial({color: 0x232323, roughness: 0.6})
  }

  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.62, 1.1, 12, 24), materials.top)
  body.position.y = 0.35
  body.scale.set(1.1, 1, 0.72)
  group.add(body)

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.48, 24, 18), materials.skin)
  head.position.y = 1.78
  group.add(head)

  const hair = new THREE.Mesh(
    new THREE.SphereGeometry(0.56, 24, 16, 0, Math.PI * 2, 0, Math.PI * 0.72),
    materials.hair
  )
  hair.position.y = 1.91
  hair.scale.set(1, 0.92, 0.92)
  group.add(hair)

  addLimb(THREE, group, materials.top, -0.78, 0.35)
  addLimb(THREE, group, materials.top, 0.78, 0.35)
  addLimb(THREE, group, materials.bottom, -0.22, -1.02, 0.18, 0.8)
  addLimb(THREE, group, materials.bottom, 0.22, -1.02, 0.18, 0.8)

  const floor = new THREE.Mesh(
    new THREE.CircleGeometry(1.25, 40),
    new THREE.MeshBasicMaterial({color: 0xc8d0ca, transparent: true, opacity: 0.78})
  )
  floor.rotation.x = -Math.PI / 2
  floor.position.y = -1.86
  scene.add(floor)

  let latestConfig = mergeConfig(config)
  const resizeObserver = new ResizeObserver(resize)
  resizeObserver.observe(container)
  renderer.setAnimationLoop(render)
  resize()
  applyConfig(latestConfig)

  return {
    scene,
    camera,
    renderer,
    update(nextConfig) {
      latestConfig = mergeConfig(nextConfig)
      applyConfig(latestConfig)
    },
    dispose() {
      resizeObserver.disconnect()
      renderer.setAnimationLoop(null)
      renderer.dispose()
      container.replaceChildren()
    }
  }

  function applyConfig(nextConfig) {
    const colors = nextConfig.colors
    const parts = nextConfig.parts
    const morph = nextConfig.faceMorph
    materials.skin.color.set(colors.skin)
    materials.hair.color.set(colors.hair)
    materials.top.color.set(TOP_COLORS[parts.top] || TOP_COLORS["top.basic_01"])
    materials.bottom.color.set(BOTTOM_COLORS[parts.bottom] || BOTTOM_COLORS["bottom.basic_01"])
    materials.shoes.color.set(SHOE_COLORS[parts.shoes] || SHOE_COLORS["shoes.basic_01"])
    head.scale.set(morph.widthScale, morph.heightScale, 0.82 + morph.depth * 0.18)
  }

  function resize() {
    const rect = container.getBoundingClientRect()
    const width = Math.max(1, rect.width)
    const height = Math.max(1, rect.height)
    camera.aspect = width / height
    camera.updateProjectionMatrix()
    renderer.setSize(width, height, false)
  }

  function render(time) {
    if (autoRotate) group.rotation.y = time / 3600
    renderer.render(scene, camera)
  }
}

function mergeConfig(config) {
  return {
    ...DEFAULT_CONFIG,
    ...config,
    colors: {...DEFAULT_CONFIG.colors, ...(config?.colors || {})},
    faceMorph: {...DEFAULT_CONFIG.faceMorph, ...(config?.faceMorph || {})},
    parts: {...DEFAULT_CONFIG.parts, ...(config?.parts || {})}
  }
}

function addLimb(THREE, group, material, x, y, radius = 0.17, length = 0.82) {
  const limb = new THREE.Mesh(new THREE.CapsuleGeometry(radius, length, 10, 16), material)
  limb.position.set(x, y, 0)
  limb.rotation.z = x < 0 ? -0.04 : 0.04
  group.add(limb)
}
