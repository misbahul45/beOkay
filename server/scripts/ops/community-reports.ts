import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { moderationService } from "../../src/features/community/moderation.service.ts";

const [cmd, membershipId, ...note] = process.argv.slice(2);
const usage = "Pemakaian: bun run scripts/ops/community-reports.ts list | uphold <membershipId> [catatan] | dismiss <membershipId> [catatan]";

if (cmd === "list") {
  const q = await moderationService.queue();
  if (!q.length) console.log("Tidak ada laporan terbuka.");
  for (const r of q) console.log(`${r.membershipId}\t${r.alias}\t${r.community ?? "-"}\t${r.reports} laporan\t${r.hidden ? "disembunyikan" : "tampil"}\t${JSON.stringify(r.reasons)}`);
} else if ((cmd === "uphold" || cmd === "dismiss") && membershipId) {
  console.log(JSON.stringify(await moderationService.resolve(membershipId, cmd, note.length ? note.join(" ").slice(0, 300) : null)));
} else {
  console.error(usage);
  process.exitCode = 2;
}
await prisma.$disconnect();
