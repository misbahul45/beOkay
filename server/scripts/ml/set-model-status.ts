/**
 * Mengubah status model di registri. Dijalankan pemilik di dalam container:
 *   docker compose run --rm api bun run scripts/ml/set-model-status.ts <modelKey> <version> <STATUS> "<catatan>"
 * APPROVED hanya boleh bila evaluasi tanpa duplikat tersedia dan akurasinya ≥ 0,90, dan catatan persetujuan ≥ 20 karakter.
 */
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const [modelKey, version, status, note = ""] = process.argv.slice(2);
const STATUSES = ["RESEARCH_ONLY", "SHADOW", "APPROVED", "DEPRECATED"];
if (!modelKey || !version || !STATUSES.includes(status ?? "")) {
  console.error("Pemakaian: set-model-status.ts <modelKey> <version> <RESEARCH_ONLY|SHADOW|APPROVED|DEPRECATED> \"<catatan>\"");
  process.exit(2);
}
const row = await prisma.modelVersion.findUnique({ where: { modelKey_version: { modelKey, version } } });
if (!row) {
  console.error("Model tidak terdaftar.");
  process.exit(1);
}
if (status === "APPROVED") {
  const acc = (row.evaluation as { test_deduplicated?: { accuracy?: number } }).test_deduplicated?.accuracy;
  if (typeof acc !== "number" || acc < 0.9) {
    console.error(`Ditolak: akurasi uji tanpa duplikat tidak ada atau < 0,90 (${acc ?? "tidak ada"}).`);
    process.exit(1);
  }
  if (note.trim().length < 20) {
    console.error("Ditolak: catatan persetujuan minimal 20 karakter (siapa, kapan, risiko yang diketahui).");
    process.exit(1);
  }
}
const updated = await prisma.modelVersion.update({ where: { id: row.id }, data: { status, approvedAt: status === "APPROVED" ? new Date() : null, approvalNote: status === "APPROVED" ? note.trim() : null } });
console.log(JSON.stringify({ modelKey: updated.modelKey, version: updated.version, status: updated.status, approvedAt: updated.approvedAt }));
await prisma.$disconnect();
