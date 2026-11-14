
import {
  lazy,
  Suspense,
  useEffect,
  useRef,
  useState,
} from "react";
import type {
  PointerEvent as ReactPointerEvent,
  ReactNode,
} from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useGSAP } from "@gsap/react";
import {
  Activity,
  ArrowDown,
  ArrowRight,
  ArrowUpRight,
  BrainCircuit,
  Check,
  ChevronDown,
  CircleCheck,
  Download,
  Footprints,
  Heart,
  HeartHandshake,
  HeartPulse,
  LockKeyhole,
  Menu,
  MoonStar,
  ShieldCheck,
  Sparkles,
  Target,
  Utensils,
  Watch,
  X,
} from "lucide-react";
import "./app.css";

gsap.registerPlugin(ScrollTrigger, useGSAP);

const Phone3D = lazy(
  () => import("./components/phone-3d")
);

const APK = {
  href: "https://beokay-api.vercel.app/beokay.apk",
  version: "1.1.2",
  size: "34,1 MB",
  sha256:
    "ac05625bc0ad84039dea563fb6dd98e2e2125a2be0e46568a97603c7edf405c4",
};

const NAV = [
  { label: "Cara kerja", href: "#cara-kerja" },
  { label: "Fitur", href: "#fitur" },
  { label: "Tiga jalur", href: "#jalur" },
  { label: "Privasi", href: "#privasi" },
  { label: "FAQ", href: "#tanya-jawab" },
];

const STEPS = [
  {
    title: "Ceritakan harimu",
    description:
      "Catat makan, aktivitas, tidur, atau glukosa bila relevan. Mulai dari yang paling mudah.",
    Icon: Utensils,
  },
  {
    title: "Hubungkan perangkat",
    description:
      "Sinkronkan langkah, tidur, dan latihan melalui Health Connect dengan izinmu.",
    Icon: Watch,
  },
  {
    title: "Lihat gambaran utuh",
    description:
      "Pahami pola harian dan mingguan, termasuk data yang masih berupa perkiraan.",
    Icon: Activity,
  },
  {
    title: "Dapatkan saran kecil",
    description:
      "Asisten menawarkan satu langkah realistis yang berangkat dari catatanmu.",
    Icon: Sparkles,
  },
  {
    title: "Kamu pegang kendali",
    description:
      "Setujui, ubah, atau tolak sarannya. Tidak otomatis disimpan tanpa persetujuan.",
    Icon: CircleCheck,
  },
];

const FEATURES = [
  {
    number: "01",
    kicker: "DAILY COACH",
    title: "Langkah kecil yang terasa mungkin.",
    description:
      "Saran mengikuti catatanmu, bukan target sempurna. Setiap tindakan menunggu keputusanmu.",
    image: "/img/screen-home.webp",
    imageAlt:
      "Tampilan beranda aplikasi beOkay dengan ringkasan dan langkah berikutnya",
    tone: "mint",
    Icon: Target,
  },
  {
    number: "02",
    kicker: "CONNECTED WELLNESS",
    title: "Lebih paham, tanpa menebak-nebak.",
    description:
      "Perangkat yang terhubung membantu merangkum gerak dan tidur; data yang tumpang tindih dihitung sekali.",
    image: "/img/screen-devices.webp",
    imageAlt:
      "Tampilan integrasi dan status data perangkat di beOkay",
    tone: "blue",
    Icon: Watch,
  },
  {
    number: "03",
    kicker: "THOUGHTFUL AI",
    title: "Asisten yang tahu kapan harus berhenti.",
    description:
      "Penjelasan menyertakan batas kepastian. Pertanyaan medis berisiko dialihkan ke tenaga kesehatan.",
    image: "/img/screen-assistant.webp",
    imageAlt:
      "Tampilan asisten beOkay dengan informasi dan label kepastian",
    tone: "violet",
    Icon: BrainCircuit,
  },
  {
    number: "04",
    kicker: "BETTER TOGETHER",
    title: "Sehat bareng, tanpa adu angka kesehatan.",
    description:
      "Misi tim merayakan konsistensi bersama dengan menampilkan progres agregat, bukan data kesehatan pribadi.",
    image: "/img/screen-team.webp",
    imageAlt:
      "Tampilan progres misi tim di aplikasi beOkay",
    tone: "peach",
    Icon: HeartHandshake,
  },
] as const;

const JOURNEYS = [
  {
    title: "Pencegahan",
    badge: "Build healthy habits",
    description:
      "Untuk kamu yang pernah diberi tahu tenaga kesehatan bahwa kamu berisiko atau mengalami prediabetes. Mulai dari kebiasaan kecil dan pengingat pemeriksaan rutin.",
    bullets: [
      "Rutinitas yang realistis",
      "Materi pencegahan sesuai ketersediaan",
      "Pengingat pemeriksaan",
    ],
    Icon: ShieldCheck,
  },
  {
    title: "Dukungan diabetes tipe 2",
    badge: "Stay informed",
    description:
      "Catat asupan, aktivitas, glukosa, dan obat bila relevan. Keputusan diagnosis serta pengobatan tetap bersama tenaga kesehatan.",
    bullets: [
      "Catatan harian terhubung",
      "Konteks yang bisa ditinjau",
      "Keputusan medis tetap pada klinisi",
    ],
    Icon: HeartPulse,
  },
  {
    title: "Gaya hidup sehat",
    badge: "Feel your best",
    description:
      "Beri ruang untuk bergerak, makan, dan istirahat lebih teratur tanpa harus mengejar rutinitas yang sempurna.",
    bullets: [
      "Keseimbangan aktivitas dan istirahat",
      "Check-in yang sederhana",
      "Target kecil berkelanjutan",
    ],
    Icon: Footprints,
  },
];

const PRIVACY = [
  {
    title: "Izin yang jelas",
    description:
      "Persetujuan diberikan per tujuan penggunaan data dan dapat dicabut.",
    Icon: LockKeyhole,
  },
  {
    title: "Ingatan dalam kendali",
    description:
      "Tinjau, koreksi, jeda, atau hapus informasi yang diingat asisten.",
    Icon: BrainCircuit,
  },
  {
    title: "Batas medis yang aman",
    description:
      "Bukan pengganti diagnosis atau keputusan pengobatan oleh klinisi.",
    Icon: ShieldCheck,
  },
  {
    title: "Data tetap milikmu",
    description:
      "Ekspor catatan atau ajukan penghapusan akun dari aplikasi.",
    Icon: Heart,
  },
];

const FAQ = [
  {
    question: "Apa sebenarnya beOkay?",
    answer:
      "beOkay adalah aplikasi Android untuk memahami kebiasaan sehat sehari-hari, mulai dari makan, aktivitas, dan tidur hingga glukosa atau obat bila relevan. Asistennya dapat menyarankan langkah kecil dari catatanmu.",
  },
  {
    question: "Apakah ini aplikasi diagnosis diabetes?",
    answer:
      "Tidak. beOkay bukan alat diagnosis, tidak memberikan dosis obat, dan tidak menggantikan tenaga kesehatan. Untuk keputusan medis, konsultasikan dengan klinisi.",
  },
  {
    question: "Apakah harus mempunyai smartwatch?",
    answer:
      "Tidak. Kamu tetap bisa mencatat secara manual. Jika perangkatmu mengirimkan data ke Health Connect, sebagian informasi dapat disinkronkan setelah kamu memberi izin.",
  },
  {
    question: "Bagaimana cara kerja asisten AI-nya?",
    answer:
      "Asisten membaca konteks yang kamu izinkan, membantu memahami catatan, dan dapat menawarkan satu langkah kecil. Kamu bisa meninjau sarannya sebelum menyimpan tindakan apa pun.",
  },
  {
    question: "Apakah informasi pribadiku aman?",
    answer:
      "beOkay dirancang dengan persetujuan per tujuan serta kontrol untuk memeriksa dan menghapus ingatan asisten. Selalu tinjau izin dan kebijakan privasi aplikasi sebelum menghubungkan data kesehatan.",
  },
  {
    question: "Apakah beOkay gratis?",
    answer:
      "Versi pilot beOkay saat ini dapat diunduh tanpa biaya. Ketersediaan fitur dapat berubah seiring pengembangan.",
  },
  {
    question: "Bagaimana memasang file APK?",
    answer:
      "Unduh APK melalui tombol resmi pada halaman ini. Android mungkin akan meminta izin pemasangan dari sumber tersebut. Pastikan kamu mengunduh dari tautan resmi beOkay.",
  },
];

function supportsWebGL() {
  try {
    const canvas = document.createElement("canvas");
    const context =
      canvas.getContext("webgl2") ??
      canvas.getContext("webgl");

    const available = Boolean(context);

    context
      ?.getExtension("WEBGL_lose_context")
      ?.loseContext();

    return available;
  } catch {
    return false;
  }
}

function BrandMark({
  className = "",
}: {
  className?: string;
}) {
  return (
    <svg
      className={className}
      viewBox="0 0 64 64"
      fill="none"
      aria-hidden="true"
    >
      <rect
        x="2"
        y="2"
        width="60"
        height="60"
        rx="21"
        fill="currentColor"
        fillOpacity="0.10"
      />
      <path
        d="M17 34.5c3.5-10.5 10-16.5 16-16.5 6.8 0 10.6 4.5 10.6 10.3 0 6-4.6 10.2-10.2 10.2-4.1 0-7.2-2.6-7.2-6.4 0-3.2 2.6-5.3 5.2-5.3 2.3 0 4.1 1.5 4.1 3.7"
        stroke="currentColor"
        strokeWidth="5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle
        cx="46.2"
        cy="43"
        r="4.2"
        fill="currentColor"
      />
    </svg>
  );
}

function Brand({
  inverse = false,
}: {
  inverse?: boolean;
}) {
  return (
    <a
      className={`bo-brand${
        inverse ? " bo-brand--inverse" : ""
      }`}
      href="#beranda"
      aria-label="beOkay, kembali ke beranda"
    >
      <BrandMark className="bo-brand__mark" />
      <span>
        be
        <span className="bo-brand__accent">
          Okay
        </span>
        <span className="bo-brand__period">
          .
        </span>
      </span>
    </a>
  );
}

function DownloadButton({
  light = false,
  children = "Unduh aplikasi",
}: {
  light?: boolean;
  children?: ReactNode;
}) {
  return (
    <a
      className={`bo-button bo-button--primary${
        light ? " bo-button--light" : ""
      }`}
      href={APK.href}
      target="_blank"
      rel="noopener noreferrer"
    >
      <Download
        size={18}
        strokeWidth={2.2}
        aria-hidden="true"
      />
      <span>{children}</span>
      <ArrowUpRight
        size={17}
        aria-hidden="true"
      />
    </a>
  );
}

function Header() {
  const [scrolled, setScrolled] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () =>
      setScrolled(window.scrollY > 40);

    handleScroll();

    window.addEventListener(
      "scroll",
      handleScroll,
      { passive: true }
    );

    return () =>
      window.removeEventListener(
        "scroll",
        handleScroll
      );
  }, []);

  useEffect(() => {
    if (!menuOpen) return;

    const onEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setMenuOpen(false);
      }
    };

    window.addEventListener(
      "keydown",
      onEscape
    );

    return () =>
      window.removeEventListener(
        "keydown",
        onEscape
      );
  }, [menuOpen]);

  return (
    <header
      className={`bo-header${
        scrolled || menuOpen
          ? " bo-header--scrolled"
          : ""
      }`}
    >
      <div className="bo-container bo-header__inner">
        <Brand
          inverse={!scrolled && !menuOpen}
        />

        <nav
          className="bo-nav"
          aria-label="Navigasi utama"
        >
          {NAV.map((item) => (
            <a
              key={item.href}
              href={item.href}
            >
              {item.label}
            </a>
          ))}
        </nav>

        <div className="bo-header__actions">
          <a
            className="bo-header__cta"
            href={APK.href}
            target="_blank"
            rel="noopener noreferrer"
          >
            Download APK
            <ArrowUpRight size={16} />
          </a>

          <button
            type="button"
            className="bo-menu-button"
            aria-label={
              menuOpen
                ? "Tutup menu"
                : "Buka menu"
            }
            aria-expanded={menuOpen}
            aria-controls="bo-mobile-menu"
            onClick={() =>
              setMenuOpen((open) => !open)
            }
          >
            {menuOpen ? (
              <X size={24} />
            ) : (
              <Menu size={24} />
            )}
          </button>
        </div>
      </div>

      <nav
        id="bo-mobile-menu"
        className={`bo-mobile-nav${
          menuOpen
            ? " bo-mobile-nav--open"
            : ""
        }`}
        aria-label="Navigasi seluler"
        inert={!menuOpen}
      >
        {NAV.map((item) => (
          <a
            key={item.href}
            href={item.href}
            onClick={() =>
              setMenuOpen(false)
            }
          >
            {item.label}
            <ArrowUpRight size={19} />
          </a>
        ))}

        <a
          href={APK.href}
          target="_blank"
          rel="noopener noreferrer"
          onClick={() =>
            setMenuOpen(false)
          }
        >
          Unduh untuk Android
          <Download size={19} />
        </a>
      </nav>
    </header>
  );
}

function PhoneFallback() {
  return (
    <div
      className="bo-phone-fallback"
      aria-label="Pratinjau tampilan aplikasi beOkay"
    >
      <div className="bo-phone-fallback__speaker" />

      <img
        src="/img/screen-home.webp"
        alt="Contoh layar utama beOkay"
        width={360}
        height={780}
        fetchPriority="high"
      />
    </div>
  );
}

function Hero() {
  const [webgl, setWebgl] = useState(false);

  useEffect(() => {
    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    );

    if (
      !reducedMotion.matches &&
      supportsWebGL()
    ) {
      setWebgl(true);
    }
  }, []);

  const handlePointerMove = (
    event: ReactPointerEvent<HTMLElement>
  ) => {
    if (event.pointerType === "touch") {
      return;
    }

    const bounds =
      event.currentTarget.getBoundingClientRect();

    event.currentTarget.style.setProperty(
      "--mouse-x",
      `${event.clientX - bounds.left}px`
    );

    event.currentTarget.style.setProperty(
      "--mouse-y",
      `${event.clientY - bounds.top}px`
    );
  };

  return (
    <section
      className="bo-hero"
      id="beranda"
      onPointerMove={handlePointerMove}
    >
      <div
        className="bo-hero__glow bo-hero__glow--one"
        aria-hidden="true"
      />
      <div
        className="bo-hero__glow bo-hero__glow--two"
        aria-hidden="true"
      />
      <div
        className="bo-hero__grid-pattern"
        aria-hidden="true"
      />

      <div className="bo-container bo-hero__layout">
        <div className="bo-hero__content">
          <div className="bo-kicker bo-kicker--hero bo-hero-enter">
            <span className="bo-live-dot" />
            YOUR EVERYDAY WELLNESS COMPANION
          </div>

          <h1 className="bo-hero__title bo-hero-enter">
            Hidup lebih sehat.
            <br />
            <span>Dengan caramu.</span>
          </h1>

          <p className="bo-hero__description bo-hero-enter">
            Satu tempat untuk memahami pola
            makan, gerak, dan tidurmu. Dibantu
            AI yang mengenal konteks,
            menghargai pilihan, dan memulai
            dari satu langkah kecil.
          </p>

          <div className="bo-hero__buttons bo-hero-enter">
            <DownloadButton>
              Unduh untuk Android
            </DownloadButton>

            <a
              className="bo-button bo-button--ghost"
              href="#cara-kerja"
            >
              Jelajahi beOkay
              <ArrowRight size={19} />
            </a>
          </div>

          <p className="bo-hero__note bo-hero-enter">
            <Check size={16} />
            Gratis selama pilot
            <span />
            Tidak memerlukan smartwatch
          </p>
        </div>

        <div
          className="bo-hero__visual"
          aria-label="Ilustrasi tiga dimensi aplikasi beOkay"
        >
          <div
            className="bo-hero__halo"
            aria-hidden="true"
          />
          <div
            className="bo-orbit bo-orbit--outer"
            aria-hidden="true"
          />
          <div
            className="bo-orbit bo-orbit--inner"
            aria-hidden="true"
          />

          <div className="bo-hero__phone bo-hero-enter">
            {webgl ? (
              <Suspense
                fallback={<PhoneFallback />}
              >
                <Phone3D className="bo-hero__canvas" />
              </Suspense>
            ) : (
              <PhoneFallback />
            )}
          </div>

          <div
            className="bo-floating-pill bo-floating-pill--steps"
            aria-hidden="true"
          >
            <span className="bo-floating-pill__icon bo-floating-pill__icon--mint">
              <Footprints size={20} />
            </span>

            <span>
              <small>Langkah hari ini</small>
              <strong>
                8.532 <i>langkah</i>
              </strong>
            </span>

            <span className="bo-pill-trend">
              ↗
            </span>
          </div>

          <div
            className="bo-floating-pill bo-floating-pill--sleep"
            aria-hidden="true"
          >
            <span className="bo-floating-pill__icon bo-floating-pill__icon--violet">
              <MoonStar size={20} />
            </span>

            <span>
              <small>Durasi tidur</small>
              <strong>7j 12m</strong>
            </span>
          </div>

          <div
            className="bo-floating-advice"
            aria-hidden="true"
          >
            <Sparkles size={16} />
            <span>
              Satu langkah kecil setiap hari
            </span>
            <CircleCheck size={17} />
          </div>

          <span className="bo-hero__mock-note">
            * Visual dan angka merupakan ilustrasi
          </span>
        </div>
      </div>

      <a
        className="bo-hero__scroll"
        href="#ringkasan"
      >
        <span>SCROLL TO EXPLORE</span>
        <ArrowDown size={17} />
      </a>

      <div
        className="bo-hero__bottom-glow"
        aria-hidden="true"
      />
    </section>
  );
}

function SectionHeading({
  eyebrow,
  title,
  description,
  centered = false,
}: {
  eyebrow: string;
  title: ReactNode;
  description?: string;
  centered?: boolean;
}) {
  return (
    <div
      className={`bo-section-heading${
        centered
          ? " bo-section-heading--center"
          : ""
      }`}
      data-reveal
    >
      <span className="bo-kicker">
        <span className="bo-kicker__line" />
        {eyebrow}
      </span>

      <h2>{title}</h2>

      {description && (
        <p>{description}</p>
      )}
    </div>
  );
}

function Intro() {
  return (
    <section
      className="bo-intro bo-section"
      id="ringkasan"
    >
      <div className="bo-container">
        <SectionHeading
          eyebrow="BUILT AROUND REAL LIFE"
          title={
            <>
              Kesehatan bukan soal angka saja.{" "}
              <span className="bo-text-accent">
                Ini tentang keseharianmu.
              </span>
            </>
          }
          description="Catatan yang terpisah sering terasa membingungkan. beOkay membantu mengubahnya menjadi gambaran utuh yang lebih mudah dipahami dan ditindaklanjuti."
          centered
        />

        <div className="bo-intro__benefits">
          <article
            className="bo-benefit"
            data-reveal
          >
            <span className="bo-benefit__icon bo-benefit__icon--green">
              <Activity size={23} />
            </span>
            <h3>Satu gambaran utuh</h3>
            <p>
              Satukan catatan makan,
              aktivitas, tidur, dan data
              perangkat yang kamu izinkan.
            </p>
          </article>

          <article
            className="bo-benefit"
            data-reveal
          >
            <span className="bo-benefit__icon bo-benefit__icon--blue">
              <Sparkles size={23} />
            </span>
            <h3>AI yang kontekstual</h3>
            <p>
              Pahami kebiasaanmu tanpa perlu
              membaca dashboard yang rumit.
            </p>
          </article>

          <article
            className="bo-benefit"
            data-reveal
          >
            <span className="bo-benefit__icon bo-benefit__icon--purple">
              <Heart size={23} />
            </span>
            <h3>Berjalan sesuai ritmemu</h3>
            <p>
              Mulai dari langkah kecil dan
              tetap bebas memilih yang tepat
              untukmu.
            </p>
          </article>
        </div>
      </div>
    </section>
  );
}

function Flow() {
  return (
    <section
      className="bo-flow bo-section"
      id="cara-kerja"
    >
      <div className="bo-container">
        <div className="bo-flow__head">
          <SectionHeading
            eyebrow="HOW IT WORKS"
            title={
              <>
                Lima langkah sederhana.
                <br />
                <span className="bo-text-accent">
                  Semuanya mulai darimu.
                </span>
              </>
            }
            description="Tidak harus mengubah semuanya hari ini. Mulai dari satu catatan dan biarkan gambaran besarnya terbentuk."
          />

          <span
            className="bo-flow__counter"
            aria-hidden="true"
          >
            01 <span>/ 05</span>
          </span>
        </div>

        <ol className="bo-flow__list">
          {STEPS.map(
            ({
              title,
              description,
              Icon,
            }, index) => (
              <li
                className="bo-flow__step"
                data-reveal
                key={title}
              >
                <div className="bo-flow__icon">
                  <Icon
                    size={25}
                    strokeWidth={1.8}
                  />
                  <span>
                    {String(index + 1).padStart(
                      2,
                      "0"
                    )}
                  </span>
                </div>

                <h3>{title}</h3>
                <p>{description}</p>

                {index < STEPS.length - 1 && (
                  <ArrowRight
                    className="bo-flow__arrow"
                    size={19}
                    aria-hidden="true"
                  />
                )}
              </li>
            )
          )}
        </ol>
      </div>
    </section>
  );
}

function MiniChart() {
  return (
    <svg
      className="bo-showcase-chart"
      viewBox="0 0 520 190"
      role="img"
      aria-label="Ilustrasi garis tren aktivitas yang meningkat"
    >
      <defs>
        <linearGradient
          id="bo-chart-fill"
          x1="0"
          x2="0"
          y1="0"
          y2="1"
        >
          <stop
            offset="0%"
            stopColor="#23cdb7"
            stopOpacity=".34"
          />
          <stop
            offset="100%"
            stopColor="#23cdb7"
            stopOpacity="0"
          />
        </linearGradient>

        <linearGradient
          id="bo-chart-stroke"
          x1="0"
          x2="1"
          y1="0"
          y2="0"
        >
          <stop
            offset="0%"
            stopColor="#65ead7"
          />
          <stop
            offset="100%"
            stopColor="#5a9ffc"
          />
        </linearGradient>
      </defs>

      <path
        d="M0 155H520M0 105H520M0 55H520"
        stroke="#dce8e9"
        strokeDasharray="5 9"
      />

      <path
        d="M0 148 C46 150 56 120 100 129 S168 104 203 114 S269 67 305 82 S370 44 405 57 S465 21 520 24 V190 H0Z"
        fill="url(#bo-chart-fill)"
      />

      <path
        d="M0 148 C46 150 56 120 100 129 S168 104 203 114 S269 67 305 82 S370 44 405 57 S465 21 520 24"
        fill="none"
        stroke="url(#bo-chart-stroke)"
        strokeWidth="5"
        strokeLinecap="round"
      />

      <circle
        cx="405"
        cy="57"
        r="8"
        fill="#fff"
        stroke="#3ab9c4"
        strokeWidth="4"
      />
    </svg>
  );
}

function Showcase() {
  return (
    <section
      className="bo-showcase bo-section"
      aria-label="Cuplikan aplikasi"
    >
      <div className="bo-container">
        <div
          className="bo-showcase__surface"
          data-reveal
        >
          <div className="bo-showcase__copy">
            <span className="bo-kicker bo-kicker--hero">
              <span className="bo-kicker__line" />
              YOUR DAY, IN FOCUS
            </span>

            <h2>
              Semua bagian harimu.
              <br />
              <span>
                Terasa lebih terhubung.
              </span>
            </h2>

            <p>
              Bukan sekadar menghitung.
              Lihat perkembangan, pahami
              konteks, dan temukan langkah
              berikutnya dari hal-hal yang
              benar-benar kamu lakukan.
            </p>

            <div className="bo-showcase__tag">
              <CircleCheck size={18} />
              Ringkasan sesuai data yang
              tersedia
            </div>
          </div>

          <div className="bo-showcase__art">
            <div className="bo-showcase__chart-card">
              <div className="bo-showcase__chart-head">
                <span>Gambaran aktivitas</span>
                <Activity size={19} />
              </div>

              <MiniChart />

              <small>
                Ilustrasi data, bukan hasil
                pengguna
              </small>
            </div>

            <div className="bo-showcase__phone">
              <img
                src="/img/screen-memory.webp"
                alt="Contoh layar pengaturan ingatan asisten beOkay"
                loading="lazy"
                width={360}
                height={780}
              />
            </div>

            <div className="bo-showcase__floating">
              <Sparkles size={18} />
              <span>
                Lebih personal.
                <br />
                <strong>
                  Tetap dalam kendalimu.
                </strong>
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Features() {
  return (
    <section
      className="bo-features bo-section"
      id="fitur"
    >
      <div className="bo-container">
        <SectionHeading
          eyebrow="FEATURES THAT MATTER"
          title={
            <>
              Lebih dari aplikasi pencatat.
              <br />
              <span className="bo-text-accent">
                Teman untuk terus bertumbuh.
              </span>
            </>
          }
          description="Kemampuan yang dirancang untuk saling melengkapi: catatan, pemahaman, saran, dan dukungan sosial."
        />

        <div className="bo-features__grid">
          {FEATURES.map(
            ({
              number,
              kicker,
              title,
              description,
              image,
              imageAlt,
              tone,
              Icon,
            }) => (
              <article
                className={`bo-feature bo-feature--${tone}`}
                key={number}
                data-reveal
              >
                <div className="bo-feature__copy">
                  <div className="bo-feature__top">
                    <span className="bo-feature__number">
                      {number} / 04
                    </span>

                    <span className="bo-feature__icon">
                      <Icon
                        size={22}
                        strokeWidth={1.8}
                      />
                    </span>
                  </div>

                  <span className="bo-feature__kicker">
                    {kicker}
                  </span>

                  <h3>{title}</h3>
                  <p>{description}</p>
                </div>

                <div className="bo-feature__visual">
                  <span
                    className="bo-feature__halo"
                    aria-hidden="true"
                  />

                  <div className="bo-feature__device">
                    <img
                      src={image}
                      alt={imageAlt}
                      width={360}
                      height={780}
                      loading="lazy"
                    />
                  </div>
                </div>
              </article>
            )
          )}
        </div>
      </div>
    </section>
  );
}

function Journeys() {
  const [active, setActive] = useState(0);

  const current = JOURNEYS[active];
  const Icon = current.Icon;

  return (
    <section
      className="bo-journeys bo-section"
      id="jalur"
    >
      <div className="bo-container">
        <SectionHeading
          eyebrow="A PATH FOR EVERY YOU"
          title={
            <>
              Tidak semua orang memulai
              <br />
              dari{" "}
              <span className="bo-text-accent">
                tempat yang sama.
              </span>
            </>
          }
          description="Pilih jalur yang sesuai dengan kondisimu. Sistem mengikuti pilihanmu, bukan menebak diagnosis dari data."
        />

        <div
          className="bo-journeys__layout"
          data-reveal
        >
          <div
            className="bo-journeys__tabs"
            role="tablist"
            aria-label="Jalur pendampingan"
          >
            {JOURNEYS.map(
              (journey, index) => {
                const JourneyIcon =
                  journey.Icon;

                return (
                  <button
                    key={journey.title}
                    type="button"
                    id={`bo-journey-tab-${index}`}
                    role="tab"
                    aria-selected={
                      active === index
                    }
                    aria-controls="bo-journey-panel"
                    tabIndex={
                      active === index
                        ? 0
                        : -1
                    }
                    className={`bo-journeys__tab${
                      active === index
                        ? " bo-journeys__tab--active"
                        : ""
                    }`}
                    onClick={() =>
                      setActive(index)
                    }
                    onKeyDown={(event) => {
                      if (
                        event.key ===
                          "ArrowDown" ||
                        event.key ===
                          "ArrowRight"
                      ) {
                        event.preventDefault();

                        const next =
                          (index + 1) %
                          JOURNEYS.length;

                        setActive(next);

                        document
                          .getElementById(
                            `bo-journey-tab-${next}`
                          )
                          ?.focus();
                      } else if (
                        event.key ===
                          "ArrowUp" ||
                        event.key ===
                          "ArrowLeft"
                      ) {
                        event.preventDefault();

                        const next =
                          (index +
                            JOURNEYS.length -
                            1) %
                          JOURNEYS.length;

                        setActive(next);

                        document
                          .getElementById(
                            `bo-journey-tab-${next}`
                          )
                          ?.focus();
                      }
                    }}
                  >
                    <span className="bo-journeys__tab-icon">
                      <JourneyIcon size={21} />
                    </span>

                    <span>
                      {journey.title}
                    </span>

                    <ArrowUpRight
                      className="bo-journeys__tab-arrow"
                      size={20}
                    />
                  </button>
                );
              }
            )}
          </div>

          <div
            id="bo-journey-panel"
            role="tabpanel"
            aria-labelledby={`bo-journey-tab-${active}`}
            className="bo-journeys__panel"
            key={active}
          >
            <div className="bo-journeys__panel-top">
              <span className="bo-journeys__badge">
                <Icon size={16} />
                {current.badge}
              </span>

              <BrandMark className="bo-journeys__watermark" />
            </div>

            <h3>{current.title}</h3>

            <p>{current.description}</p>

            <ul>
              {current.bullets.map(
                (bullet) => (
                  <li key={bullet}>
                    <Check size={16} />
                    {bullet}
                  </li>
                )
              )}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
}

function Privacy() {
  return (
    <section
      className="bo-privacy bo-section"
      id="privasi"
    >
      <div className="bo-container">
        <div className="bo-privacy__layout">
          <div className="bo-privacy__intro">
            <SectionHeading
              eyebrow="PRIVACY BY DESIGN"
              title={
                <>
                  Datamu. Pilihanmu.
                  <br />
                  <span className="bo-text-accent">
                    Selalu.
                  </span>
                </>
              }
              description="Kesehatan adalah hal personal. Karena itu kendali atas data, ingatan asisten, dan setiap saran harus tetap berada di tanganmu."
            />

            <div className="bo-privacy__seal">
              <ShieldCheck size={23} />
              Designed with consent-first
              principles
            </div>
          </div>

          <div className="bo-privacy__cards">
            {PRIVACY.map(
              ({
                title,
                description,
                Icon,
              }) => (
                <article
                  className="bo-privacy__card"
                  data-reveal
                  key={title}
                >
                  <span>
                    <Icon
                      size={23}
                      strokeWidth={1.8}
                    />
                  </span>

                  <h3>{title}</h3>
                  <p>{description}</p>
                </article>
              )
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

function Cta() {
  return (
    <section
      className="bo-cta"
      id="unduh"
    >
      <div className="bo-container">
        <div
          className="bo-cta__panel"
          data-reveal
        >
          <div
            className="bo-cta__orb bo-cta__orb--one"
            aria-hidden="true"
          />
          <div
            className="bo-cta__orb bo-cta__orb--two"
            aria-hidden="true"
          />

          <div className="bo-cta__content">
            <div className="bo-kicker bo-kicker--hero">
              <span className="bo-live-dot" />
              YOUR NEXT CHAPTER STARTS HERE
            </div>

            <h2>
              Langkah kecil hari ini.
              <br />
              <span>
                Perubahan berarti nanti.
              </span>
            </h2>

            <p>
              Mulai mengenal pola hidupmu
              dengan lebih baik. Satu hari,
              satu keputusan, satu langkah
              pada satu waktu.
            </p>

            <DownloadButton light>
              Mulai dengan beOkay
            </DownloadButton>

            <div className="bo-cta__meta">
              <span>
                <Check size={15} />
                Android APK
              </span>
              <span>
                Versi {APK.version}
              </span>
              <span>{APK.size}</span>
            </div>
          </div>

          <div
            className="bo-cta__art"
            aria-hidden="true"
          >
            <span className="bo-cta__art-ring" />

            <BrandMark className="bo-cta__giant-mark" />

            <span className="bo-cta__art-spark">
              <Sparkles size={32} />
            </span>
          </div>
        </div>

        <details className="bo-apk-details">
          <summary>
            Detail file & verifikasi
            keamanan
            <ChevronDown size={16} />
          </summary>

          <div>
            <p>
              Unduh hanya dari tautan resmi
              di halaman ini. Cocokkan
              SHA-256 berkas yang diunduh
              jika ingin memverifikasi
              integritasnya.
            </p>

            <code>{APK.sha256}</code>
          </div>
        </details>
      </div>
    </section>
  );
}

function Faq() {
  return (
    <section
      className="bo-faq bo-section"
      id="tanya-jawab"
    >
      <div className="bo-container bo-faq__layout">
        <div className="bo-faq__intro">
          <SectionHeading
            eyebrow="GOOD TO KNOW"
            title={
              <>
                Masih penasaran?
                <br />
                <span className="bo-text-accent">
                  Kami jelaskan.
                </span>
              </>
            }
            description="Jawaban singkat untuk pertanyaan yang paling sering muncul tentang beOkay."
          />
        </div>

        <div className="bo-faq__items">
          {FAQ.map((item) => (
            <details
              className="bo-faq__item"
              key={item.question}
            >
              <summary>
                <span>
                  {item.question}
                </span>

                <span className="bo-faq__toggle">
                  <ChevronDown size={20} />
                </span>
              </summary>

              <div className="bo-faq__answer">
                {item.answer}
              </div>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="bo-footer">
      <div className="bo-container">
        <div className="bo-footer__main">
          <div>
            <Brand inverse />

            <p>
              Small steps. A healthier story.
              <br />
              Satu langkah kecil,
              setiap hari.
            </p>
          </div>

          <div className="bo-footer__links">
            <span>JELAJAHI</span>

            {NAV.map((item) => (
              <a
                key={item.href}
                href={item.href}
              >
                {item.label}
              </a>
            ))}
          </div>

          <div className="bo-footer__links">
            <span>PRODUK</span>

            <a
              href={APK.href}
              target="_blank"
              rel="noopener noreferrer"
            >
              Unduh Android
              <ArrowUpRight size={14} />
            </a>

            <a href="/health">
              Status API
              <ArrowUpRight size={14} />
            </a>
          </div>
        </div>

        <div className="bo-footer__disclaimer">
          <p>
            beOkay bukan alat diagnosis dan
            tidak menggantikan tenaga kesehatan.
            Jangan mengubah obat atau pengobatan
            berdasarkan informasi aplikasi.
            Konten edukasi klinis yang belum
            ditinjau belum tersedia untuk
            penggunaan produksi.
          </p>

          <p>
            Angka, grafik, dan sebagian visual
            pada halaman ini merupakan contoh
            ilustratif, bukan hasil atau
            jaminan kesehatan pengguna.
          </p>
        </div>

        <div className="bo-footer__bottom">
          <span>
            © {new Date().getFullYear()} beOkay.
            All rights reserved.
          </span>

          <span>
            Made for better days
            <Heart
              size={14}
              fill="currentColor"
            />
          </span>

          <a href="#beranda">
            Kembali ke atas ↑
          </a>
        </div>
      </div>
    </footer>
  );
}

export default function App() {
  const root = useRef<HTMLDivElement>(null);

  useGSAP(
    () => {
      const mm = gsap.matchMedia();

      mm.add(
        "(prefers-reduced-motion: no-preference)",
        () => {
          gsap.fromTo(
            ".bo-hero-enter",
            {
              autoAlpha: 0,
              y: 35,
            },
            {
              autoAlpha: 1,
              y: 0,
              duration: 1.05,
              stagger: 0.12,
              ease: "power3.out",
              delay: 0.1,
            }
          );

          gsap.utils
            .toArray<HTMLElement>(
              "[data-reveal]"
            )
            .forEach((element) => {
              gsap.fromTo(
                element,
                {
                  autoAlpha: 0,
                  y: 42,
                },
                {
                  autoAlpha: 1,
                  y: 0,
                  duration: 0.9,
                  ease: "power2.out",
                  scrollTrigger: {
                    trigger: element,
                    start: "top 88%",
                    once: true,
                  },
                }
              );
            });

          gsap.to(
            ".bo-hero__halo",
            {
              y: -65,
              rotate: 13,
              ease: "none",
              scrollTrigger: {
                trigger: ".bo-hero",
                start: "top top",
                end: "bottom top",
                scrub: true,
              },
            }
          );

          gsap.to(
            ".bo-showcase__phone",
            {
              y: -45,
              ease: "none",
              scrollTrigger: {
                trigger: ".bo-showcase",
                start: "top bottom",
                end: "bottom top",
                scrub: true,
              },
            }
          );
        }
      );

      return () => mm.revert();
    },
    {
      scope: root,
    }
  );

  return (
    <div
      className="bo-app"
      ref={root}
    >
      <a
        className="bo-skip-link"
        href="#ringkasan"
      >
        Lewati ke konten utama
      </a>

      <Header />

      <main>
        <Hero />
        <Intro />
        <Flow />
        <Showcase />
        <Features />
        <Journeys />
        <Privacy />
        <Cta />
        <Faq />
      </main>

      <Footer />
    </div>
  );
}
