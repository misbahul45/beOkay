import { useEffect, useRef } from "react";
import {
  AmbientLight,
  BufferAttribute,
  Clock,
  DirectionalLight,
  Group,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  Scene,
  Shape,
  ShapeGeometry,
  SRGBColorSpace,
  TextureLoader,
  WebGLRenderer,
  type Texture,
} from "three";
import { RoundedBoxGeometry } from "three/examples/jsm/geometries/RoundedBoxGeometry.js";

const W = 1.62;
const H = 3.38;
const D = 0.2;
const R = 0.24;
const BEZEL = 0.07;

function roundedPlane(w: number, h: number, r: number) {
  const s = new Shape();
  const x = -w / 2;
  const y = -h / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y);
  s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r);
  s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h);
  s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r);
  s.quadraticCurveTo(x, y, x + r, y);
  const g = new ShapeGeometry(s, 12);
  const uv = g.attributes.uv as BufferAttribute;
  const pos = g.attributes.position as BufferAttribute;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, (pos.getX(i) - x) / w, (pos.getY(i) - y) / h);
  return g;
}

export default function Phone3D({ className }: { className?: string }) {
  const host = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const renderer = new WebGLRenderer({ antialias: true, alpha: true, powerPreference: "low-power" });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));
    renderer.outputColorSpace = SRGBColorSpace;
    renderer.domElement.style.cssText = "display:block;width:100%;height:100%";
    el.appendChild(renderer.domElement);

    const scene = new Scene();
    const camera = new PerspectiveCamera(32, 1, 0.1, 50);
    camera.position.set(0, 0, 6.4);
    scene.add(new AmbientLight(0xffffff, 0.9));
    const key = new DirectionalLight(0xffffff, 1.6);
    key.position.set(-3, 4, 5);
    const rim = new DirectionalLight(0xffe2b8, 0.8);
    rim.position.set(4, -2, -3);
    scene.add(key, rim);

    const body = new RoundedBoxGeometry(W, H, D, 6, R);
    const face = roundedPlane(W - BEZEL * 2, H - BEZEL * 2, R - BEZEL);
    const island = roundedPlane(0.42, 0.11, 0.055);
    const back = new PlaneGeometry(0.9, 0.9);
    const bodyMat = new MeshStandardMaterial({ color: 0x1b2326, metalness: 0.55, roughness: 0.32 });
    const faceMat = new MeshBasicMaterial({ color: 0xf7f7f4, toneMapped: false });
    const islandMat = new MeshBasicMaterial({ color: 0x0d1214 });
    const backMat = new MeshBasicMaterial({ transparent: true, opacity: 0, toneMapped: false });

    const phone = new Group();
    phone.rotation.set(0.08, -0.42, 0.04);
    const faceMesh = new Mesh(face, faceMat);
    faceMesh.position.z = D / 2 + 0.002;
    const islandMesh = new Mesh(island, islandMat);
    islandMesh.position.set(0, H / 2 - BEZEL - 0.12, D / 2 + 0.004);
    const backMesh = new Mesh(back, backMat);
    backMesh.position.set(0, 0.35, -D / 2 - 0.002);
    backMesh.rotation.y = Math.PI;
    phone.add(new Mesh(body, bodyMat), faceMesh, islandMesh, backMesh);
    scene.add(phone);

    const render = () => renderer.render(scene, camera);
    const textures: Texture[] = [];
    const loader = new TextureLoader();
    const prepare = (t: Texture) => {
      t.colorSpace = SRGBColorSpace;
      t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
      textures.push(t);
    };
    loader.load("/img/screen-home.webp", (t) => {
      prepare(t);
      faceMat.map = t;
      faceMat.color.set(0xffffff);
      faceMat.needsUpdate = true;
      render();
    });
    loader.load("/img/logo-mark.webp", (t) => {
      prepare(t);
      backMat.map = t;
      backMat.opacity = 1;
      backMat.needsUpdate = true;
      render();
    });

    const resize = () => {
      const { width, height } = el.getBoundingClientRect();
      if (!width || !height) return;
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      render();
    };
    const ro = new ResizeObserver(resize);
    ro.observe(el);
    resize();

    const input = { x: 0, y: 0, scroll: 0 };
    const move = (e: PointerEvent) => {
      input.x = (e.clientX / window.innerWidth) * 2 - 1;
      input.y = (e.clientY / window.innerHeight) * 2 - 1;
    };
    const scroll = () => {
      input.scroll = Math.min(1, Math.max(0, window.scrollY / window.innerHeight));
    };
    const clock = new Clock();
    const tick = () => {
      const dt = Math.min(clock.getDelta(), 0.1);
      const t = clock.elapsedTime;
      const k = 1 - Math.exp(-dt * 4);
      const ty = -0.42 + input.scroll * 1.35 + input.x * 0.28 + Math.sin(t * 0.5) * 0.06;
      const tx = 0.08 - input.y * 0.16 + Math.sin(t * 0.7) * 0.02;
      phone.rotation.y += (ty - phone.rotation.y) * k;
      phone.rotation.x += (tx - phone.rotation.x) * k;
      phone.position.y = Math.sin(t * 0.9) * 0.06 - input.scroll * 0.4;
      render();
    };

    let io: IntersectionObserver | undefined;
    if (!still) {
      scroll();
      window.addEventListener("pointermove", move, { passive: true });
      window.addEventListener("scroll", scroll, { passive: true });
      io = new IntersectionObserver(
        ([e]) => {
          if (e.isIntersecting) {
            clock.getDelta();
            renderer.setAnimationLoop(tick);
          } else {
            renderer.setAnimationLoop(null);
          }
        },
        { rootMargin: "80px" },
      );
      io.observe(el);
    }

    return () => {
      renderer.setAnimationLoop(null);
      io?.disconnect();
      ro.disconnect();
      window.removeEventListener("pointermove", move);
      window.removeEventListener("scroll", scroll);
      for (const g of [body, face, island, back]) g.dispose();
      for (const m of [bodyMat, faceMat, islandMat, backMat]) m.dispose();
      for (const t of textures) t.dispose();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  return <div ref={host} className={className} role="img" aria-label="Ponsel beOkay menampilkan Beranda dengan kartu langkah berikutnya" />;
}
