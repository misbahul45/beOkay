import { authenticated } from "../auth/guard.ts";
import { readImage } from "./image.ts";
import { foodVisionService } from "./food-vision.service.ts";

export const foodVisionRoutes = {
  "/api/me/foods/scan/label": {
    POST: authenticated(async ({ req, session }) => ({
      body: await foodVisionService.scanLabel(session.userId, await readImage(req)),
    })),
  },
  "/api/me/foods/scan/photo": {
    POST: authenticated(async ({ req, session }) => ({
      body: await foodVisionService.identifyPhoto(session.userId, await readImage(req)),
    })),
  },
};
