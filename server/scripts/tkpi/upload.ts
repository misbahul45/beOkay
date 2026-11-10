/**
 * Mengunggah berkas sumber (PDF TKPI) ke UploadThing agar rujukan sumber RAG tersimpan di luar mesin pengembang.
 *
 *   bun run scripts/tkpi/upload.ts <berkas.pdf>
 *
 * Token dibaca dari env UPLOADTHING_TOKEN (tidak dicetak). Berkas dikirim sebagai privat bila akun mengizinkan.
 */
import { UTApi } from "uploadthing/server";
import { env } from "../../src/config/env.ts";

const path = process.argv[2];
if (!path) throw new Error("Pemakaian: bun run scripts/tkpi/upload.ts <berkas.pdf>");
if (!env.UPLOADTHING_TOKEN) throw new Error("UPLOADTHING_TOKEN tidak ada di env.");

const file = Bun.file(path);
if (!(await file.exists())) throw new Error("Berkas tidak ditemukan.");
if (file.size > 32 * 1024 * 1024) throw new Error("Berkas terlalu besar untuk skrip ini (>32 MB).");
const name = path.split("/").pop()!;
const bytes = new Uint8Array(await file.arrayBuffer());
const sha256 = new Bun.CryptoHasher("sha256").update(bytes).digest("hex");

const utapi = new UTApi({ token: env.UPLOADTHING_TOKEN });
const result = await utapi.uploadFiles(new File([bytes], name, { type: "application/pdf" }));
if (result.error) {
  console.log(JSON.stringify({ event: "upload_failed", code: result.error.code, message: result.error.message }));
  process.exit(1);
}
console.log(JSON.stringify({ event: "upload_ok", key: result.data.key, name: result.data.name, size: result.data.size, sha256, url: result.data.ufsUrl ?? result.data.url }));
