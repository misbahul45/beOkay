import { authenticated } from "../auth/guard.ts";
import { FEATURE_LABELS, featureFlags } from "./feature-flags.service.ts";

export const featureFlagRoutes = {
  "/api/me/features": {
    GET: authenticated(async () => {
      const values = await featureFlags.all();
      return { body: { features: values, labels: FEATURE_LABELS } };
    }),
  },
};
