import { authenticated } from "../auth/guard.ts";
import { readImage } from "./image.ts";
import { dishService } from "../ml/dish.service.ts";
import { foodVisionService } from "./food-vision.service.ts";

/** Perkiraan model tidak boleh menahan hasil utama lebih dari ini. */
const HINT_WAIT_MS = 4_000;

export const foodVisionRoutes = {
  "/api/me/foods/scan/label": {
    POST: authenticated(async ({ req, session }) => ({
      body: await foodVisionService.scanLabel(session.userId, await readImage(req)),
    })),
  },
  "/api/me/foods/scan/photo": {
    POST: authenticated(async ({ req, session }) => {
      const image = await readImage(req);
      // Model Modal: non-APPROVED hanya bayangan (tak memengaruhi respons); APPROVED memberi PERKIRAAN terpisah yang tidak pernah dicatat otomatis.
      const assist = dishService.assist(session.userId, image.bytes);
      const result = await foodVisionService.identifyPhoto(session.userId, image);
      const hint = await Promise.race([assist, new Promise<null>((r) => setTimeout(() => r(null), HINT_WAIT_MS))]);
      return { body: hint ? { ...result, modelHint: { kind: "ESTIMATE", label: hint.label, probability: hint.probability, modelVersion: hint.modelVersion, note: "Perkiraan nama hidangan dari model yang masih diuji. Periksa sebelum dipakai; tidak dicatat otomatis." } } : result };
    }),
  },
};
