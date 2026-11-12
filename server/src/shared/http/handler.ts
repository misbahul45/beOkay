import type { Server } from "bun";
import { ZodError, type ZodType } from "zod";
import { AppError, badRequest } from "../errors/app-error.ts";
import { logEvent } from "./logger.ts";
import { metrics } from "../../infrastructure/observability/metrics.ts";
import { applySecurityHeaders } from "./security-headers.ts";

const MAX_BODY_BYTES = 64 * 1024;

export type RequestContext = {
  req: Request;
  server: Server<unknown>;
  requestId: string;
  log: { userId?: string };
};

export type Result = Response | { status?: number; body: unknown };

function toResponse(result: Result): Response {
  if (result instanceof Response) return result;
  return Response.json(result.body, { status: result.status ?? 200 });
}

function errorResponse(error: unknown, requestId: string): Response {
  if (error instanceof AppError) {
    const body: Record<string, unknown> = { code: error.code, message: error.message, requestId };
    if (error.details) body.details = error.details;
    return Response.json({ error: body }, { status: error.status });
  }
  if (error instanceof ZodError) {
    const issues = error.issues.map((issue) => ({ path: issue.path.join("."), code: issue.code }));
    return Response.json(
      { error: { code: "VALIDATION_ERROR", message: "Data yang dikirim tidak valid.", details: { issues }, requestId } },
      { status: 400 },
    );
  }
  logEvent("error", "unhandled_error", {
    requestId,
    name: error instanceof Error ? error.name : "unknown",
  });
  return Response.json(
    { error: { code: "INTERNAL_ERROR", message: "Terjadi kendala di server. Coba lagi nanti.", requestId } },
    { status: 500 },
  );
}

export function route(handler: (context: RequestContext) => Promise<Result>) {
  return async (req: Request, server: Server<unknown>): Promise<Response> => {
    const requestId = crypto.randomUUID();
    const started = performance.now();
    const path = new URL(req.url).pathname;
    const log: RequestContext["log"] = {};
    let response: Response;
    try {
      response = toResponse(await handler({ req, server, requestId, log }));
    } catch (error) {
      response = errorResponse(error, requestId);
    }
    const headers = new Headers(response.headers);
    headers.set("X-Request-Id", requestId);
    applySecurityHeaders(headers, { noStore: true, page: path.startsWith("/s/") || path.startsWith("/api/auth/"), production: process.env.NODE_ENV === "production" });
    metrics.observeRequest(req.method, path, response.status, performance.now() - started);
    logEvent("info", "request", {
      requestId,
      method: req.method,
      path,
      status: response.status,
      durationMs: Math.round(performance.now() - started),
      userId: log.userId,
    });
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  };
}

export async function readJson<T>(req: Request, schema: ZodType<T>): Promise<T> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) throw new AppError(413, "PAYLOAD_TOO_LARGE", "Data yang dikirim terlalu besar.");
  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    throw new AppError(415, "UNSUPPORTED_MEDIA_TYPE", "Gunakan Content-Type application/json.");
  }
  const text = await req.text();
  if (text.length > MAX_BODY_BYTES) throw new AppError(413, "PAYLOAD_TOO_LARGE", "Data yang dikirim terlalu besar.");
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw badRequest("MALFORMED_JSON", "Format JSON tidak valid.");
  }
  return schema.parse(raw);
}
