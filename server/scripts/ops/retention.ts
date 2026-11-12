import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { defaultRetention, retentionService } from "../../src/features/retention/retention.service.ts";

try {
  const dryRun = !process.argv.includes("--apply");
  console.log(JSON.stringify(await retentionService.run(defaultRetention(), new Date(), { dryRun }), null, 2));
  if (dryRun) console.error("Mode uji kering. Tambahkan --apply untuk benar-benar menghapus.");
} finally {
  await prisma.$disconnect();
}
