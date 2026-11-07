import { unauthorized } from "../../shared/errors/app-error.ts";
import { route, type RequestContext, type Result } from "../../shared/http/handler.ts";
import { auth } from "./auth.ts";

export type AuthenticatedSession = {
  userId: string;
  email: string;
  emailVerified: boolean;
  sessionId: string;
};

export type AuthenticatedContext = RequestContext & { session: AuthenticatedSession };

export async function resolveSession(headers: Headers): Promise<AuthenticatedSession | null> {
  const result = await auth.api.getSession({ headers });
  if (!result) return null;
  return {
    userId: result.user.id,
    email: result.user.email,
    emailVerified: result.user.emailVerified,
    sessionId: result.session.id,
  };
}

export function authenticated(handler: (context: AuthenticatedContext) => Promise<Result>) {
  return route(async (context) => {
    const session = await resolveSession(context.req.headers);
    if (!session || !session.emailVerified) throw unauthorized();
    context.log.userId = session.userId;
    return handler({ ...context, session });
  });
}
