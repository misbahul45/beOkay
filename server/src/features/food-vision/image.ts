import { AppError, badRequest } from "../../shared/errors/app-error.ts";

export const MAX_IMAGE_BYTES = 1_500_000;
export type ImageMime = "image/jpeg" | "image/png" | "image/webp";

/** Tipe ditentukan dari byte pertama berkas, bukan dari header yang dikirim klien. */
export function sniffImage(bytes: Uint8Array): ImageMime | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return "image/png";
  if (
    bytes.length >= 12 &&
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
  )
    return "image/webp";
  return null;
}

/** Membaca badan biner dengan batas ukuran; gambar tidak pernah ditulis ke disk atau database. */
export async function readImage(req: Request): Promise<{ bytes: Uint8Array; mime: ImageMime }> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_IMAGE_BYTES) throw new AppError(413, "IMAGE_TOO_LARGE", "Foto terlalu besar. Ambil ulang dengan resolusi lebih kecil.");
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (bytes.length === 0) throw badRequest("IMAGE_REQUIRED", "Foto tidak ditemukan.");
  if (bytes.length > MAX_IMAGE_BYTES) throw new AppError(413, "IMAGE_TOO_LARGE", "Foto terlalu besar. Ambil ulang dengan resolusi lebih kecil.");
  const mime = sniffImage(bytes);
  if (!mime) throw badRequest("IMAGE_UNSUPPORTED", "Format foto tidak didukung. Gunakan JPEG, PNG, atau WebP.");
  return { bytes, mime };
}

export const toDataUrl = (bytes: Uint8Array, mime: ImageMime) => `data:${mime};base64,${Buffer.from(bytes).toString("base64")}`;
