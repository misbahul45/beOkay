export type ErrorDetails = Record<string, unknown>;

export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: ErrorDetails,
  ) {
    super(message);
    this.name = "AppError";
  }
}

export const badRequest = (code: string, message: string, details?: ErrorDetails) =>
  new AppError(400, code, message, details);
export const unauthorized = () => new AppError(401, "UNAUTHENTICATED", "Sesi tidak valid atau sudah berakhir.");
export const forbidden = (code: string, message: string, details?: ErrorDetails) =>
  new AppError(403, code, message, details);
export const notFound = (code: string, message: string) => new AppError(404, code, message);
export const conflict = (code: string, message: string, details?: ErrorDetails) =>
  new AppError(409, code, message, details);
export const unprocessable = (code: string, message: string, details?: ErrorDetails) =>
  new AppError(422, code, message, details);
