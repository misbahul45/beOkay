import { checkDatabase, prisma } from "./infrastructure/database/prisma.ts";
import { auth } from "./lib/auth.ts";

const port = Number(process.env.PORT ?? 3000);

const server = Bun.serve({
  port,
  routes: {
    "/api/auth/*": (req) => auth.handler(req),
    "/health": async () => {
      const db = await checkDatabase();
      return Response.json({ status: db ? "ok" : "degraded", db }, { status: db ? 200 : 503 });
    },
  },
});

console.log(`beOkay API listening on :${server.port}`);

async function shutdown() {
  await server.stop();
  await prisma.$disconnect();
  process.exit(0);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
