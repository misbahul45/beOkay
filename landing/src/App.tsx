import { lazy, Suspense, useEffect, useLayoutEffect, useRef, useState } from "react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useGSAP } from "@gsap/react";
import { ArrowRight, ChevronRight, Download, Menu } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { Sheet, SheetClose, SheetContent, SheetDescription, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";

gsap.registerPlugin(ScrollTrigger, useGSAP);

const Phone3D = lazy(() => import("@/components/phone-3d"));

function canUseWebGL() {
  try {
    const c = document.createElement("canvas");
    return !!(c.getContext("webgl2") ?? c.getContext("webgl"));
  } catch {
    return false;
  }
}

const APK_URL = "/beokay.apk";
const APK = { url: "https://beokay-api.vercel.app/beokay.apk", version: "1.1.2", size: "34,1 MB", sha256: "ac05625bc0ad84039dea563fb6dd98e2e2125a2be0e46568a97603c7edf405c4" };
const MOTION = "(prefers-reduced-motion: no-preference)";

const NAV = [
  { href: "#cara-kerja", label: "Cara kerja" },
  { href: "#jalur", label: "Tiga jalur" },
  { href: "#fitur", label: "Fitur" },
  { href: "#privasi", label: "Privasi" },
  { href: "#tanya-jawab", label: "Tanya jawab" },
];

function Header() {
  const [solid, setSolid] = useState(false);
  useEffect(() => {
    const onScroll = () => setSolid(window.scrollY > window.innerHeight * 0.6);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  return (
    <header className={cn("fixed inset-x-0 top-0 z-40 transition-colors duration-300", solid ? "bg-cream/90 backdrop-blur-md" : "bg-transparent")}>
      <div className="mx-auto flex h-20 max-w-[1440px] items-center justify-between px-5 md:px-[60px]">
        <a href="#beranda" aria-label="beOkay, kembali ke atas" className="rounded-lg focus-visible:ring-2 focus-visible:ring-ring">
          <img src="/img/logo-full.webp" alt="beOkay" width={152} height={47} className="h-9 w-auto md:h-11" />
        </a>
        <div className="flex items-center gap-3 md:gap-4">
          <Sheet>
            <SheetTrigger asChild>
              <Button variant="secondary" size="icon" aria-label="Buka menu" className="bg-sand">
                <Menu />
              </Button>
            </SheetTrigger>
            <SheetContent>
              <SheetTitle>Menu</SheetTitle>
              <SheetDescription>Navigasi halaman beOkay</SheetDescription>
              <nav className="mt-6 flex flex-col">
                {NAV.map((n) => (
                  <SheetClose asChild key={n.href}>
                    <a href={n.href} className="border-b border-line py-4 text-2xl text-ink hover:text-brand">
                      {n.label}
                    </a>
                  </SheetClose>
                ))}
              </nav>
              <Button asChild size="lg" className="mt-8">
                <a href={APK_URL}>
                  <Download /> Unduh untuk Android
                </a>
              </Button>
            </SheetContent>
          </Sheet>
          <Button asChild size="sm" className="h-11 sm:hidden">
            <a href={APK_URL} aria-label="Unduh APK Android">
              <Download /> Unduh APK
            </a>
          </Button>
          <Button asChild className="hidden sm:inline-flex">
            <a href={APK_URL}>Unduh untuk Android</a>
          </Button>
        </div>
      </div>
    </header>
  );
}

function Hero() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      const mm = gsap.matchMedia();
      mm.add(MOTION, () => {
        gsap.from(".hero-line", { yPercent: 110, opacity: 0, duration: 1.1, stagger: 0.12, ease: "power3.out", delay: 0.15 });
        gsap.from(".hero-mark", { scale: 0.85, opacity: 0, duration: 1.4, ease: "power2.out" });
        gsap.to(".hero-sky", { yPercent: 12, ease: "none", scrollTrigger: { trigger: root.current, start: "top top", end: "bottom top", scrub: true } });
        gsap.to(".hero-mark", { yPercent: -30, rotate: 8, ease: "none", scrollTrigger: { trigger: root.current, start: "top top", end: "bottom top", scrub: true } });
      });
    },
    { scope: root },
  );
  const [webgl, setWebgl] = useState(false);
  useEffect(() => setWebgl(canUseWebGL()), []);
  const mark = <img src="/img/logo-mark.webp" alt="" aria-hidden width={384} height={384} className="hero-mark absolute top-[20%] right-[10%] w-[26vw] max-w-[300px] drop-shadow-[0_24px_40px_rgba(15,76,92,0.18)]" />;
  return (
    <section id="beranda" ref={root} className="relative h-[100svh] min-h-[640px] overflow-hidden">
      <div className="hero-sky absolute inset-0 -top-[6%] h-[112%] bg-[linear-gradient(180deg,#79c3e0_0%,#bfe2ec_38%,#f2d7a1_72%,#e7af67_100%)]" />
      <div aria-hidden className="absolute top-[14%] right-[6%] size-[42vw] max-h-[460px] max-w-[460px] rounded-full bg-[#fff6de]/60 blur-[2px]" />
      <div aria-hidden className="absolute inset-x-0 bottom-0 h-[62%] bg-[linear-gradient(0deg,rgba(74,42,14,0.62)_0%,rgba(74,42,14,0.32)_45%,rgba(74,42,14,0)_100%)]" />
      {webgl ? (
        <Suspense fallback={mark}>
          <Phone3D className="absolute top-[9%] right-[-12%] h-[56%] w-[78vw] sm:right-[-4%] md:top-[8%] md:right-[4%] md:h-[80%] md:w-[42vw] md:max-w-[620px]" />
        </Suspense>
      ) : (
        mark
      )}
      <div className="relative mx-auto flex h-full max-w-[1440px] flex-col justify-end px-5 pb-14 md:px-[100px] md:pb-16">
        <h1 className="max-w-[980px] text-[44px] leading-[1.08] text-white sm:text-6xl md:text-[80px] md:leading-[1.18] md:tracking-[-0.8px]">
          <span className="block overflow-hidden pb-[0.08em]"><span className="hero-line block">Hubungan baru dengan</span></span>
          <span className="block overflow-hidden pb-[0.08em]"><span className="hero-line block">kebiasaan sehatmu</span></span>
        </h1>
        <a href="#unduh" className="mt-8 w-fit text-xl text-white/95 hover:text-white">Gulir</a>
      </div>
    </section>
  );
}

function DownloadStrip() {
  return (
    <section id="unduh" className="bg-[#5a3a1c]">
      <div className="mx-auto flex max-w-[1440px] flex-col gap-5 px-5 py-12 md:px-[100px]">
        <p className="text-xl text-white">Unduh aplikasinya</p>
        <div className="flex flex-wrap gap-4">
          <Button asChild variant="light" size="store">
            <a href={APK_URL}>
              <Download /> Android (APK)
            </a>
          </Button>
          <Button asChild variant="light" size="store">
            <a href="#cara-kerja">
              Lihat cara kerja <ArrowRight />
            </a>
          </Button>
        </div>
      </div>
    </section>
  );
}

function Intro() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add(MOTION, () => {
        gsap.from(".intro-reveal", { y: 40, opacity: 0, duration: 0.9, stagger: 0.12, ease: "power2.out", scrollTrigger: { trigger: root.current, start: "top 70%" } });
      });
    },
    { scope: root },
  );
  return (
    <section id="ringkasan" ref={root} className="mx-auto max-w-[1100px] px-5 pt-28 pb-10 text-center md:pt-40">
      <h2 className="intro-reveal text-4xl leading-[1.15] text-ink md:text-[64px] md:leading-[1.18] md:tracking-[-0.5px]">
        Semua kebiasaan sehatmu
        <br className="hidden md:block" /> di satu tempat
      </h2>
      <p className="intro-reveal mx-auto mt-10 max-w-[880px] text-xl leading-relaxed text-ink md:text-[30px] md:leading-[1.45]">
        beOkay menyatukan catatan makan, aktivitas, tidur, dan data dari Health Connect menjadi satu gambaran yang mudah dibaca, lalu menyarankan satu langkah kecil berikutnya.
      </p>
      <Button asChild className="intro-reveal mt-12">
        <a href="#cara-kerja">Lihat cara kerjanya</a>
      </Button>
    </section>
  );
}

const STEPS = [
  { title: "Catat", text: "Makan, aktivitas, tidur, dan glukosa bila relevan. Cukup ketik atau pakai suara." },
  { title: "Sambungkan", text: "Langkah, tidur, dan sesi latihan dari Health Connect, dengan izin per jenis data." },
  { title: "Pahami pola", text: "Ringkasan harian dan mingguan. Angka dari perangkat ditandai sebagai perkiraan." },
  { title: "Satu langkah kecil", text: "Asisten mengusulkan satu langkah dari catatanmu sendiri." },
  { title: "Kamu yang memutuskan", text: "Setujui, ubah, atau tolak. Tanpa persetujuanmu, tidak ada yang disimpan." },
];

function Flow() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add({ wide: "(min-width: 768px)", motion: MOTION }, (ctx) => {
        if (!ctx.conditions?.motion) return;
        const wide = ctx.conditions.wide;
        const tl = gsap.timeline({ scrollTrigger: { trigger: ".flow-list", start: "top 78%", end: wide ? "bottom 55%" : "bottom 60%", scrub: 0.6 } });
        tl.from(".flow-fill", wide ? { scaleX: 0, ease: "none", duration: 1 } : { scaleY: 0, ease: "none", duration: 1 }, 0);
        gsap.utils.toArray<HTMLElement>(".flow-step").forEach((el, i) => {
          const at = i / (STEPS.length - 1);
          tl.from(el.querySelector(".flow-dot"), { backgroundColor: "#ffffff", color: "#0f7a6c", scale: 0.86, duration: 0.08, ease: "none" }, Math.max(0, at - 0.04));
          tl.from(el.querySelectorAll(".flow-copy"), { opacity: 0.25, y: 14, duration: 0.12, ease: "none" }, Math.max(0, at - 0.06));
        });
      });
    },
    { scope: root },
  );
  return (
    <section id="cara-kerja" ref={root} className="mx-auto max-w-[1440px] px-5 pt-24 pb-10 md:px-[100px] md:pt-36">
      <p className="text-xl text-ink">Cara kerja</p>
      <h2 className="mt-3 max-w-[1000px] text-4xl leading-[1.12] text-ink md:text-[56px] md:tracking-[-0.5px]">Dari catatan kecil ke satu langkah yang kamu pilih</h2>
      <ol className="flow-list relative mt-14 grid gap-10 md:mt-20 md:grid-cols-5 md:gap-6">
        <span aria-hidden className="absolute top-7 bottom-7 left-[26px] w-1 rounded-full bg-line md:right-[10%] md:bottom-auto md:left-[10%] md:h-1 md:w-auto" />
        <span aria-hidden className="flow-fill absolute top-7 bottom-7 left-[26px] w-1 origin-top rounded-full bg-brand md:right-[10%] md:bottom-auto md:left-[10%] md:h-1 md:w-auto md:origin-left" />
        {STEPS.map((step, i) => (
          <li key={step.title} className="flow-step relative grid grid-cols-[56px_1fr] items-start gap-5 md:flex md:flex-col md:items-center md:gap-0 md:text-center">
            <span className="flow-dot relative z-10 grid size-14 place-items-center rounded-full border-2 border-brand bg-brand text-xl font-medium text-white">{i + 1}</span>
            <div>
              <h3 className="flow-copy text-2xl text-navy md:mt-6">{step.title}</h3>
              <p className="flow-copy mt-2 max-w-[260px] text-base leading-relaxed text-ink/90">{step.text}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  );
}

const CARDS = [
  { label: "Langkah", value: "8.532", tone: "bg-[#9ee6d6]", pos: "left-[4%] top-[6%] md:left-[22%] md:top-[4%]", speed: -60 },
  { label: "Tidur", value: "7 j 12 m", sub: "dari dua perangkat, dihitung sekali", tone: "bg-[#e3d6fb]", pos: "right-[4%] top-[18%] md:right-[18%] md:top-[10%]", speed: 40 },
  { label: "Hari aktif minggu ini", value: "3 dari 7", tone: "bg-[#cdefb9]", pos: "left-[8%] top-[42%] md:left-[26%] md:top-[40%]", speed: -30 },
  { label: "Energi hari ini", value: "Biasa", tone: "bg-[#ffedbe]", pos: "right-[6%] top-[52%] md:right-[16%] md:top-[46%]", speed: 70 },
  { label: "Rencana kecil", value: "Jalan kaki 10 menit", sub: "menunggu persetujuanmu", tone: "bg-white", pos: "left-[6%] bottom-[6%] md:left-[34%] md:bottom-[6%]", speed: -80 },
  { label: "Kepastian", value: "Perkiraan perangkat", tone: "bg-white", pos: "right-[4%] bottom-[2%] md:right-[26%] md:bottom-[2%]", speed: 30 },
];

function Collage() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add(MOTION, () => {
        gsap.utils.toArray<HTMLElement>(".float-card").forEach((el) => {
          gsap.from(el, { opacity: 0, scale: 0.9, duration: 0.8, ease: "power2.out", scrollTrigger: { trigger: el, start: "top 90%" } });
          gsap.to(el, { y: Number(el.dataset.speed), ease: "none", scrollTrigger: { trigger: root.current, start: "top bottom", end: "bottom top", scrub: true } });
        });
        gsap.to(".collage-mark", { rotate: 360, ease: "none", scrollTrigger: { trigger: root.current, start: "top bottom", end: "bottom top", scrub: true } });
      });
    },
    { scope: root },
  );
  return (
    <section ref={root} aria-label="Contoh ringkasan harian" className="relative mx-auto h-[760px] max-w-[1440px] px-5 md:h-[880px]">
      <img src="/img/logo-mark.webp" alt="" aria-hidden width={96} height={96} className="collage-mark absolute top-1/2 left-1/2 size-20 -translate-x-1/2 -translate-y-1/2 md:size-24" />
      {CARDS.map((c) => (
        <div key={c.label} data-speed={c.speed} className={cn("float-card absolute w-[44vw] max-w-[260px] rounded-3xl p-5 shadow-[0_10px_30px_rgba(24,37,42,0.06)]", c.tone, c.pos)}>
          <p className="text-sm font-medium text-muted-foreground">{c.label}</p>
          <p className="mt-1 text-2xl font-semibold text-ink-strong md:text-[26px]">{c.value}</p>
          {c.sub && <p className="mt-1 text-xs text-muted-foreground">{c.sub}</p>}
        </div>
      ))}
      <p className="absolute inset-x-0 bottom-[-28px] text-center text-xs text-muted-foreground">Angka pada gambar adalah contoh.³</p>
    </section>
  );
}

const JOURNEYS = [
  { name: "Pencegahan", text: "Bila tenaga kesehatan pernah bilang kamu prediabetes atau berisiko. Kebiasaan kecil, bacaan pencegahan², dan pengingat pemeriksaan rutin." },
  { name: "Dukungan diabetes tipe 2", text: "Catat makan, aktivitas, glukosa, dan obat. Pengobatan tetap bersama tim kesehatanmu." },
  { name: "Gaya hidup sehat", text: "Bergerak, makan, dan tidur sehari-hari dengan langkah yang realistis." },
];

function Journeys() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add(MOTION, () => {
        gsap.from(".journey-row", { x: -40, opacity: 0, duration: 0.8, stagger: 0.15, ease: "power2.out", scrollTrigger: { trigger: root.current, start: "top 70%" } });
      });
    },
    { scope: root },
  );
  return (
    <section id="jalur" ref={root} className="mx-auto max-w-[1440px] px-5 pt-32 pb-24 md:px-[120px] md:pt-44">
      <h2 className="text-4xl text-ink md:text-[64px] md:tracking-[-0.5px]">Dirancang untuk tiga jalur</h2>
      <p className="mt-6 max-w-[760px] text-lg text-ink/90 md:text-xl">Jalurmu ditentukan dari jawabanmu sendiri, bukan ditebak dari data. Konten untuk satu jalur tidak muncul di jalur lain.</p>
      <ul className="mt-12">
        {JOURNEYS.map((j) => (
          <li key={j.name} className="journey-row group grid gap-3 border-b border-line py-8 md:grid-cols-[1.1fr_1fr] md:items-center md:py-10">
            <h3 className="flex items-center justify-between text-3xl text-navy md:text-5xl">
              {j.name}
              <ChevronRight className="size-8 transition-transform duration-300 group-hover:translate-x-1 md:hidden" />
            </h3>
            <p className="text-lg text-ink/90">{j.text}</p>
          </li>
        ))}
      </ul>
    </section>
  );
}

function Phone({ src, alt, className }: { src: string; alt: string; className?: string }) {
  return (
    <div className={cn("rounded-[44px] bg-[#1d2428] p-[10px] shadow-[0_30px_60px_rgba(24,37,42,0.22)]", className)}>
      <img src={src} alt={alt} width={360} height={780} loading="lazy" className="block w-full rounded-[34px]" />
    </div>
  );
}

function Screens() {
  const root = useRef<HTMLElement>(null);
  useGSAP(
    () => {
      gsap.matchMedia().add(MOTION, () => {
        const st = { trigger: root.current, start: "top bottom", end: "bottom top", scrub: true };
        gsap.fromTo(".phone-a", { y: 120, rotate: -6 }, { y: -60, rotate: -2, ease: "none", scrollTrigger: st });
        gsap.fromTo(".phone-b", { y: 40, rotate: 6 }, { y: -140, rotate: 2, ease: "none", scrollTrigger: st });
      });
    },
    { scope: root },
  );
  return (
    <section ref={root} className="mx-auto max-w-[1440px] overflow-hidden px-5 pt-10 pb-28 md:px-[60px]">
      <div className="flex justify-center gap-6 md:gap-16">
        <Phone src="/img/screen-home.webp" alt="Beranda beOkay dengan kartu langkah berikutnya, progres minggu ini, dan check-in energi" className="phone-a w-[44vw] max-w-[300px]" />
        <Phone src="/img/screen-memory.webp" alt="Layar ingatan asisten dengan konflik, ingatan aktif, dan yang dijeda" className="phone-b mt-16 w-[44vw] max-w-[300px]" />
      </div>
      <h2 className="mt-24 max-w-[760px] text-3xl leading-[1.2] text-ink md:text-[40px]">Dirancang untuk tempatmu hari ini dan langkahmu berikutnya.</h2>
    </section>
  );
}

const PANELS = [
  { title: "Rencana kecil yang pas dengan harimu", text: "Asisten mengusulkan satu langkah kecil dari catatanmu sendiri, misalnya jalan kaki sepuluh menit. Tidak ada yang tersimpan sebelum kamu menyetujuinya.", tone: "bg-panel-green", src: "/img/screen-home.webp", alt: "Kartu langkah berikutnya di Beranda" },
  { title: "Tidur dan pemulihan, tanpa menebak", text: "Langkah, tidur, dan sesi latihan dari Health Connect digabung dengan jujur: waktu yang direkam dua perangkat dihitung sekali, dan hari tanpa data tidak dianggap tidak aktif.", tone: "bg-panel-indigo", src: "/img/screen-devices.webp", alt: "Status data perangkat 14 hari terakhir" },
  { title: "Asisten yang tahu batasnya", text: "Jawaban bacaan selalu membawa label kepastian dan sumbernya. Pertanyaan tentang dosis atau diagnosis diarahkan ke tenaga kesehatan.¹", tone: "bg-panel-clay", src: "/img/screen-assistant.webp", alt: "Asisten menampilkan label kepastian dan kartu strategi" },
  { title: "Bergerak bersama, tanpa membandingkan nilai kesehatan", text: "Misi tim menghitung hari aktif seluruh anggota. Yang tampil hanya jumlah tim, tanpa nama dan tanpa angka kesehatan.", tone: "bg-brand-deep", src: "/img/screen-team.webp", alt: "Progres misi tim" },
];

function Panels() {
  const root = useRef<HTMLElement>(null);
  useLayoutEffect(() => {
    const host = root.current;
    if (!host) return;
    const panels = [...host.querySelectorAll<HTMLElement>(".panel")];
    const pin = () => {
      for (const p of panels) p.style.top = `${Math.min(0, window.innerHeight - p.offsetHeight)}px`;
      ScrollTrigger.refresh();
    };
    pin();
    const ro = new ResizeObserver(pin);
    panels.forEach((p) => ro.observe(p));
    window.addEventListener("resize", pin);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", pin);
    };
  }, []);
  useGSAP(
    () => {
      gsap.matchMedia().add(MOTION, () => {
        const panels = gsap.utils.toArray<HTMLElement>(".panel");
        panels.forEach((p, i) => {
          gsap.from(p.querySelectorAll(".panel-text"), { y: 50, opacity: 0, duration: 0.9, stagger: 0.12, ease: "power2.out", scrollTrigger: { trigger: p, start: "top 65%" } });
          gsap.fromTo(p.querySelector(".panel-phone"), { y: 90 }, { y: -20, ease: "none", scrollTrigger: { trigger: p, start: "top bottom", end: "top top", scrub: true } });
          const next = panels[i + 1];
          if (next) {
            gsap.to(p.querySelector(".panel-inner"), { scale: 0.93, ease: "none", scrollTrigger: { trigger: next, start: "top bottom", end: "top top", scrub: true } });
            gsap.to(p.querySelector(".panel-shade"), { opacity: 0.45, ease: "none", scrollTrigger: { trigger: next, start: "top bottom", end: "top top", scrub: true } });
          }
        });
      });
    },
    { scope: root },
  );
  return (
    <section id="fitur" ref={root} aria-label="Fitur beOkay" className="relative">
      {PANELS.map((p, i) => (
        <article key={p.title} className={cn("panel sticky overflow-hidden rounded-t-[32px] text-white shadow-[0_-24px_60px_rgba(24,37,42,0.18)] md:rounded-t-[48px]", p.tone, i === 0 && "shadow-none")}>
          <div className="panel-inner origin-top">
            <div className="mx-auto grid max-w-[1440px] items-center gap-10 px-5 pt-20 pb-16 md:min-h-[100svh] md:grid-cols-[1.2fr_1fr] md:gap-12 md:px-[100px] md:py-20">
              <div>
                <p className="panel-text text-sm tracking-[0.12em] text-white/75 uppercase">{String(i + 1).padStart(2, "0")} / {String(PANELS.length).padStart(2, "0")}</p>
                <h2 className="panel-text mt-4 text-4xl leading-[1.12] md:text-[56px] md:tracking-[-0.56px]">{p.title}</h2>
                <p className="panel-text mt-8 max-w-[560px] text-lg leading-relaxed text-white/90 md:text-xl">{p.text}</p>
              </div>
              <Phone src={p.src} alt={p.alt} className="panel-phone mx-auto w-[56vw] max-w-[280px] md:max-w-[300px]" />
            </div>
          </div>
          <div aria-hidden className="panel-shade pointer-events-none absolute inset-0 bg-black opacity-0" />
        </article>
      ))}
    </section>
  );
}

const PRIVACY = [
  { title: "Persetujuan per tujuan", text: "Setiap pemakaian data punya persetujuannya sendiri dan bisa dicabut kapan saja." },
  { title: "Ingatan yang bisa kamu atur", text: "Lihat, jeda, koreksi, atau hapus apa pun yang diingat asisten." },
  { title: "Keselamatan didahulukan", text: "Bukan alat diagnosis. Keluhan mendesak selalu diarahkan ke tenaga kesehatan." },
  { title: "Data milikmu", text: "Ekspor seluruh catatan atau hapus akun dari aplikasi." },
];

function Privacy() {
  return (
    <section id="privasi" className="mx-auto max-w-[1440px] px-5 py-28 md:px-[120px] md:py-40">
      <h2 className="max-w-[900px] text-4xl leading-[1.15] text-ink md:text-5xl">Pribadi, proaktif, aman, dan dalam kendalimu</h2>
      <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
        {PRIVACY.map((p) => (
          <div key={p.title} className="rounded-3xl bg-white p-7">
            <h3 className="text-xl font-medium text-ink-strong">{p.title}</h3>
            <p className="mt-3 text-base leading-relaxed text-ink/90">{p.text}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

function Cta() {
  return (
    <section id="unduh-apk" className="bg-brand-deep">
      <div className="mx-auto flex max-w-[1440px] flex-col items-center gap-8 px-5 py-28 text-center md:py-36">
        <img src="/img/logo-mark.webp" alt="" aria-hidden width={88} height={88} className="size-20" />
        <h2 className="text-4xl text-white md:text-5xl">Mulai perjalanan sehatmu</h2>
        <Button asChild variant="light" size="lg">
          <a href={APK_URL}>
            <Download /> Unduh APK Android
          </a>
        </Button>
        <div className="w-full max-w-[560px] rounded-3xl bg-white/10 p-6 text-left text-white">
          <p className="text-sm text-white/80">Tautan langsung</p>
          <a href={APK_URL} className="mt-1 block break-all text-lg font-medium underline underline-offset-4">{APK.url}</a>
          <dl className="mt-4 grid grid-cols-3 gap-3 text-sm">
            <div><dt className="text-white/70">Versi</dt><dd className="font-medium">{APK.version}</dd></div>
            <div><dt className="text-white/70">Ukuran</dt><dd className="font-medium">{APK.size}</dd></div>
            <div><dt className="text-white/70">Perangkat</dt><dd className="font-medium">Android arm64</dd></div>
          </dl>
          <p className="mt-4 text-xs text-white/70">SHA-256</p>
          <p className="font-mono text-xs break-all text-white/90">{APK.sha256}</p>
        </div>
      </div>
    </section>
  );
}

const FAQ = [
  { q: "Apa itu beOkay?", a: "Aplikasi Android untuk mencatat dan menjaga kebiasaan sehat harian: makan, aktivitas, tidur, serta glukosa dan obat bila relevan. Asisten menyarankan satu langkah kecil berdasarkan catatanmu sendiri, dan tidak ada yang tersimpan tanpa persetujuanmu." },
  { q: "Apakah beOkay alat diagnosis?", a: "Bukan. beOkay tidak mendiagnosis, tidak menghitung dosis, dan tidak menggantikan tenaga kesehatan. Pertanyaan seperti itu dijawab dengan arahan untuk menghubungi tenaga kesehatan.¹" },
  { q: "Perlukah jam tangan pintar?", a: "Tidak. Catatan manual sudah cukup. Bila jam tangan atau aplikasi kebugaranmu menulis ke Health Connect, langkah, tidur, dan sesi latihan bisa diimpor setelah kamu mengizinkannya." },
  { q: "Bagaimana dengan privasiku?", a: "Setiap pemakaian data punya persetujuan terpisah yang bisa dicabut. Ingatan asisten bisa dilihat, dijeda, dan dihapus. Kamu bisa mengekspor seluruh catatan atau menghapus akun dari aplikasi." },
  { q: "Apakah beOkay gratis?", a: "Saat ini beOkay berstatus pilot dan bisa diunduh tanpa biaya." },
  { q: "Bagaimana memasang APK-nya?", a: "Unduh berkas APK dari halaman ini, izinkan pemasangan dari sumber tersebut saat diminta Android, lalu buka beOkay." },
];

function Faq() {
  return (
    <section id="tanya-jawab" className="bg-white">
      <div className="mx-auto grid max-w-[1440px] gap-10 px-5 py-28 md:grid-cols-[1fr_2fr] md:gap-20 md:px-[60px] md:py-36">
        <h2 className="text-5xl text-ink md:text-[64px]">Tanya jawab</h2>
        <Accordion type="single" collapsible defaultValue="item-0">
          {FAQ.map((f, i) => (
            <AccordionItem key={f.q} value={`item-${i}`}>
              <AccordionTrigger>{f.q}</AccordionTrigger>
              <AccordionContent>{f.a}</AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="bg-white">
      <div className="mx-auto max-w-[1440px] space-y-3 px-5 pb-10 text-[13px] leading-relaxed text-ink md:px-[60px]">
        <p><sup>1</sup> beOkay bukan alat diagnosis dan tidak memberi saran medis. Konsultasikan perubahan pengobatan dan latihan dengan tenaga kesehatanmu.</p>
        <p><sup>2</sup> Bacaan edukasi masih menunggu tinjauan klinisi dan belum ditampilkan di aplikasi produksi.</p>
        <p><sup>3</sup> Angka dan tampilan pada halaman ini adalah contoh; hasil setiap orang berbeda.</p>
      </div>
      <div className="mx-auto flex max-w-[1440px] flex-col gap-6 border-t border-line px-5 py-10 md:flex-row md:items-center md:justify-between md:px-[60px]">
        <img src="/img/logo-full.webp" alt="beOkay" width={130} height={40} className="h-9 w-auto" />
        <nav className="flex flex-wrap gap-6 text-sm text-ink">
          {NAV.map((n) => (
            <a key={n.href} href={n.href} className="hover:text-brand">{n.label}</a>
          ))}
          <a href="/health" className="hover:text-brand">Status API</a>
        </nav>
        <p className="text-sm text-muted-foreground">© 2026 beOkay</p>
      </div>
    </footer>
  );
}

export default function App() {
  return (
    <>
      <a href="#ringkasan" className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-full focus:bg-white focus:px-4 focus:py-2">Lewati ke isi</a>
      <Header />
      <main>
        <Hero />
        <DownloadStrip />
        <Intro />
        <Flow />
        <Collage />
        <Journeys />
        <Screens />
        <Panels />
        <Privacy />
        <Cta />
        <Faq />
      </main>
      <Footer />
    </>
  );
}
