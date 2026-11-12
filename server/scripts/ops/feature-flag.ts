import { FEATURE_KEYS, FEATURE_LABELS, featureFlags, type FeatureKey } from "../../src/features/feature-flags/feature-flags.service.ts";
import { prisma } from "../../src/infrastructure/database/prisma.ts";

const [cmd, key, value] = process.argv.slice(2);
const flag = (name: string) => {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const usage = () => {
  console.error("Pakai: feature-flag.ts list | set <kunci> on|off --by <nama> [--note <teks>] | clear <kunci> --by <nama>");
  console.error(`Kunci: ${FEATURE_KEYS.join(", ")}`);
  process.exit(2);
};
const isKey = (k: string | undefined): k is FeatureKey => !!k && (FEATURE_KEYS as readonly string[]).includes(k);

try {
  if (cmd === "list") {
    const values = await featureFlags.all();
    const rows = await prisma.featureFlag.findMany();
    console.log(JSON.stringify(FEATURE_KEYS.map((k) => ({ key: k, label: FEATURE_LABELS[k], enabled: values[k], override: rows.find((r) => r.key === k) ?? null })), null, 2));
  } else if (cmd === "set" && isKey(key) && (value === "on" || value === "off")) {
    const by = flag("--by");
    if (!by) usage();
    const row = await featureFlags.set(key, value === "on", by!, flag("--note") ?? null);
    console.log(JSON.stringify({ key: row.key, enabled: row.enabled, updatedBy: row.updatedBy, effectiveWithinSeconds: 30 }));
  } else if (cmd === "clear" && isKey(key)) {
    const by = flag("--by");
    if (!by) usage();
    console.log(JSON.stringify({ key, cleared: Boolean(await featureFlags.clear(key, by!)) }));
  } else usage();
} finally {
  await prisma.$disconnect();
}
