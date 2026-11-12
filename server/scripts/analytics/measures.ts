import { prisma } from "../../src/infrastructure/database/prisma.ts";
import { measuresService } from "../../src/features/usage/measures.service.ts";

const arg = (name: string) => {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
};
try {
  const to = arg("--to") ? new Date(arg("--to")! + "T00:00:00+07:00") : new Date();
  const days = Number(arg("--days") ?? 28);
  const from = arg("--from") ? new Date(arg("--from")! + "T00:00:00+07:00") : new Date(to.getTime() - days * 86_400_000);
  console.log(JSON.stringify(await measuresService.compute({ from, to }), null, 2));
} finally {
  await prisma.$disconnect();
}
