import { z } from "zod";
import { authenticated } from "../auth/guard.ts";
import { AppError } from "../../shared/errors/app-error.ts";
import { cgmService } from "./cgm.service.ts";

export const MAX_CSV_BYTES = 4 * 1024 * 1024;
const id = (req: Request) => z.uuid().parse(new URL(req.url).pathname.split("/")[5]);
const importQuery = z.object({ fileName: z.string().trim().max(200).optional(), dateOrder: z.enum(["auto", "MDY", "DMY"]).default("auto") });
const days = (req: Request) => z.coerce.number().int().refine((d) => d === 14 || d === 30 || d === 90).default(14).parse(new URL(req.url).searchParams.get("days") ?? undefined) as 14 | 30 | 90;

async function readCsv(req: Request) {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_CSV_BYTES) throw new AppError(413, "PAYLOAD_TOO_LARGE", "Berkas terlalu besar (maksimal 4 MB).");
  const type = (req.headers.get("content-type") ?? "").toLowerCase();
  if (!type.startsWith("text/csv") && !type.startsWith("text/plain")) throw new AppError(415, "UNSUPPORTED_MEDIA_TYPE", "Kirim berkas sebagai text/csv.");
  const text = await req.text();
  if (text.length > MAX_CSV_BYTES) throw new AppError(413, "PAYLOAD_TOO_LARGE", "Berkas terlalu besar (maksimal 4 MB).");
  return text;
}

export const cgmRoutes = {
  "/api/me/cgm/imports": {
    GET: authenticated(async ({ session }) => ({ body: await cgmService.list(session.userId) })),
    POST: authenticated(async ({ req, session }) => {
      const q = importQuery.parse(Object.fromEntries(new URL(req.url).searchParams));
      return { status: 201, body: await cgmService.importCsv(session.userId, await readCsv(req), q) };
    }),
  },
  "/api/me/cgm/imports/:id": { DELETE: authenticated(async ({ req, session }) => ({ body: await cgmService.remove(session.userId, id(req)) })) },
  "/api/me/cgm/summary": { GET: authenticated(async ({ req, session }) => ({ body: await cgmService.summary(session.userId, days(req)) })) },
};
