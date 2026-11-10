import { z } from "zod";

export const pushRegisterSchema = z
  .object({
    token: z.string().trim().min(20).max(4096),
    platform: z.enum(["android", "ios"]),
    appVersion: z.string().trim().max(40).optional(),
  })
  .strict();
export type PushRegister = z.infer<typeof pushRegisterSchema>;
