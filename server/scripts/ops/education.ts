import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { educationService } from "../../src/features/education/education.service.ts";

const [cmd, key, version, ...rest] = process.argv.slice(2);
const usage = "Pemakaian: bun run scripts/ops/education.ts list | sync | review <key> <version> <nama peninjau> | retire <key> <version>";

if (cmd === "list") {
  const rows = await prisma.educationModule.findMany({ orderBy: [{ key: "asc" }, { version: "asc" }], select: { key: true, version: true, title: true, reviewStatus: true, reviewedBy: true, reviewedAt: true, contentHash: true } });
  for (const r of rows) console.log(`${r.key}@${r.version}\t${r.reviewStatus}\t${r.reviewedBy ?? "-"}\t${r.reviewedAt?.toISOString().slice(0, 10) ?? "-"}\t${r.contentHash.slice(0, 12)}\t${r.title}`);
} else if (cmd === "sync") {
  console.log(JSON.stringify(await educationService.sync()));
} else if (cmd === "review" && key && version && rest.length) {
  const r = await educationService.review(key, Number(version), rest.join(" "));
  console.log(JSON.stringify({ key: r.key, version: r.version, reviewStatus: r.reviewStatus, reviewedBy: r.reviewedBy, contentHash: r.contentHash }));
} else if (cmd === "retire" && key && version) {
  const r = await educationService.retire(key, Number(version));
  console.log(JSON.stringify({ key: r.key, version: r.version, reviewStatus: r.reviewStatus }));
} else {
  console.error(usage);
  process.exitCode = 2;
}
await prisma.$disconnect();
