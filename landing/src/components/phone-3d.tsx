
import {
  Suspense,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  Canvas,
  useFrame,
} from "@react-three/fiber";
import { useTexture } from "@react-three/drei";
import * as THREE from "three";

function roundedRectangle(
  width: number,
  height: number,
  radius: number
) {
  const shape = new THREE.Shape();

  const x = -width / 2;
  const y = -height / 2;

  shape.moveTo(x + radius, y);

  shape.lineTo(
    x + width - radius,
    y
  );

  shape.quadraticCurveTo(
    x + width,
    y,
    x + width,
    y + radius
  );

  shape.lineTo(
    x + width,
    y + height - radius
  );

  shape.quadraticCurveTo(
    x + width,
    y + height,
    x + width - radius,
    y + height
  );

  shape.lineTo(
    x + radius,
    y + height
  );

  shape.quadraticCurveTo(
    x,
    y + height,
    x,
    y + height - radius
  );

  shape.lineTo(
    x,
    y + radius
  );

  shape.quadraticCurveTo(
    x,
    y,
    x + radius,
    y
  );

  return shape;
}

function Device({
  animate,
}: {
  animate: boolean;
}) {
  const group = useRef<THREE.Group>(null);

  const texture = useTexture(
    "/img/screen-home.webp"
  );

  const chassis = useMemo(
    () =>
      new THREE.ExtrudeGeometry(
        roundedRectangle(
          2.22,
          4.62,
          0.29
        ),
        {
          depth: 0.16,
          steps: 1,
          bevelEnabled: true,
          bevelThickness: 0.055,
          bevelSize: 0.025,
          bevelSegments: 3,
          curveSegments: 12,
        }
      ),
    []
  );

  const screen = useMemo(() => {
    const width = 2.07;
    const height = 4.43;

    const geometry =
      new THREE.ShapeGeometry(
        roundedRectangle(
          width,
          height,
          0.22
        ),
        18
      );

    const position =
      geometry.attributes.position;

    const uv =
      geometry.attributes.uv;

    for (
      let index = 0;
      index < position.count;
      index++
    ) {
      uv.setXY(
        index,
        (
          position.getX(index) +
          width / 2
        ) / width,
        (
          position.getY(index) +
          height / 2
        ) / height
      );
    }

    uv.needsUpdate = true;

    return geometry;
  }, []);

  useEffect(() => {
    texture.colorSpace =
      THREE.SRGBColorSpace;

    texture.anisotropy = 4;
    texture.needsUpdate = true;
  }, [texture]);

  useEffect(() => {
    return () => {
      chassis.dispose();
      screen.dispose();
    };
  }, [chassis, screen]);

  useFrame(({ clock }) => {
    if (
      !group.current ||
      !animate
    ) {
      return;
    }

    const t = clock.getElapsedTime();

    group.current.position.y =
      Math.sin(t * 0.65) * 0.105;

    group.current.rotation.y =
      -0.29 +
      Math.sin(t * 0.34) * 0.1;

    group.current.rotation.z =
      -0.06 +
      Math.sin(t * 0.5) * 0.024;
  });

  return (
    <group
      ref={group}
      rotation={[
        0.10,
        -0.29,
        -0.06,
      ]}
    >
      <mesh geometry={chassis}>
        <meshPhysicalMaterial
          color="#15222d"
          metalness={0.75}
          roughness={0.24}
          clearcoat={1}
          clearcoatRoughness={0.13}
        />
      </mesh>

      <mesh
        geometry={screen}
        position={[
          0,
          0,
          0.224,
        ]}
      >
        <meshBasicMaterial
          map={texture}
          toneMapped={false}
          side={THREE.DoubleSide}
        />
      </mesh>

      <mesh
        position={[
          0,
          2.13,
          0.236,
        ]}
      >
        <capsuleGeometry
          args={[
            0.038,
            0.18,
            4,
            12,
          ]}
        />
        <meshBasicMaterial
          color="#111a25"
        />
      </mesh>

      <mesh
        position={[
          1.13,
          0.88,
          0.07,
        ]}
      >
        <boxGeometry
          args={[
            0.035,
            0.56,
            0.12,
          ]}
        />
        <meshStandardMaterial
          color="#7b94a4"
          metalness={0.85}
          roughness={0.23}
        />
      </mesh>

      <mesh
        position={[
          -1.13,
          0.83,
          0.07,
        ]}
      >
        <boxGeometry
          args={[
            0.035,
            0.4,
            0.12,
          ]}
        />
        <meshStandardMaterial
          color="#7b94a4"
          metalness={0.85}
          roughness={0.23}
        />
      </mesh>

      <mesh
        position={[
          -1.13,
          0.33,
          0.07,
        ]}
      >
        <boxGeometry
          args={[
            0.035,
            0.4,
            0.12,
          ]}
        />
        <meshStandardMaterial
          color="#7b94a4"
          metalness={0.85}
          roughness={0.23}
        />
      </mesh>
    </group>
  );
}

export default function Phone3D({
  className = "",
}: {
  className?: string;
}) {
  const host = useRef<HTMLDivElement>(null);

  const [visible, setVisible] =
    useState(true);

  const [
    reducedMotion,
    setReducedMotion,
  ] = useState(false);

  useEffect(() => {
    const query = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    );

    const sync = () =>
      setReducedMotion(
        query.matches
      );

    sync();

    query.addEventListener(
      "change",
      sync
    );

    return () =>
      query.removeEventListener(
        "change",
        sync
      );
  }, []);

  useEffect(() => {
    const element = host.current;

    if (
      !element ||
      !(
        "IntersectionObserver" in window
      )
    ) {
      return;
    }

    const observer =
      new IntersectionObserver(
        ([entry]) => {
          setVisible(
            entry.isIntersecting
          );
        },
        {
          rootMargin: "100px",
        }
      );

    observer.observe(element);

    return () =>
      observer.disconnect();
  }, []);

  return (
    <div
      ref={host}
      className={className}
      aria-label="Model 3D ponsel dengan pratinjau beranda beOkay"
      role="img"
    >
      <Canvas
        camera={{
          position: [
            0,
            0,
            8.2,
          ],
          fov: 37,
          near: 0.1,
          far: 25,
        }}
        dpr={[
          1,
          1.5,
        ]}
        frameloop={
          visible &&
          !reducedMotion
            ? "always"
            : "demand"
        }
        gl={{
          alpha: true,
          antialias: true,
          powerPreference:
            "low-power",
        }}
        style={{
          width: "100%",
          height: "100%",
          pointerEvents: "none",
        }}
      >
        <ambientLight
          intensity={2.2}
        />

        <directionalLight
          position={[
            3,
            5,
            7,
          ]}
          intensity={3.5}
          color="#e1fff9"
        />

        <directionalLight
          position={[
            -5,
            0,
            3,
          ]}
          intensity={2.0}
          color="#95baff"
        />

        <pointLight
          position={[
            -3,
            -3,
            4,
          ]}
          intensity={1.5}
          color="#75e7dc"
        />

        <Suspense fallback={null}>
          <Device
            animate={
              visible &&
              !reducedMotion
            }
          />
        </Suspense>
      </Canvas>
    </div>
  );
}
