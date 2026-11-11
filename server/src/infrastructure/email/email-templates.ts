const escapeHtml = (value: string) =>
  value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function layout(heading: string, intro: string, actionLabel: string, url: string, footer: string) {
  const safeUrl = escapeHtml(url);
  return `<!doctype html><html lang="id"><body style="margin:0;background:#F6F8FA;font-family:Inter,Arial,sans-serif;color:#171B20"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;background:#FFFFFF;border-radius:24px;padding:32px"><tr><td><p style="margin:0 0 24px;font-weight:700;font-size:18px">beOkay</p><h1 style="margin:0 0 12px;font-size:28px;line-height:1.15">${escapeHtml(heading)}</h1><p style="margin:0 0 24px;font-size:16px;line-height:1.5;color:#566673">${escapeHtml(intro)}</p><p style="margin:0 0 24px"><a href="${safeUrl}" style="display:inline-block;background:#171B20;color:#FFFFFF;text-decoration:none;padding:14px 28px;border-radius:999px;font-weight:600">${escapeHtml(actionLabel)}</a></p><p style="margin:0 0 8px;font-size:13px;line-height:1.5;color:#566673">Jika tombol tidak berfungsi, salin tautan ini ke peramban:</p><p style="margin:0 0 24px;font-size:13px;word-break:break-all;color:#566673">${safeUrl}</p><p style="margin:0;font-size:13px;line-height:1.5;color:#566673">${escapeHtml(footer)}</p></td></tr></table></td></tr></table></body></html>`;
}

export function verificationEmail(url: string) {
  const intro = "Kami mengirim tautan ini untuk memastikan akunmu tetap aman. Tautan berlaku selama 1 jam.";
  const footer = "Jika kamu tidak membuat akun beOkay, abaikan email ini.";
  return {
    subject: "Verifikasi email beOkay",
    text: `Verifikasi emailmu\n\n${intro}\n\n${url}\n\n${footer}`,
    html: layout("Verifikasi emailmu", intro, "Verifikasi Email", url, footer),
  };
}

export function accountDeletedEmail() {
  const text = "Akun beOkay-mu dan semua catatan yang terhubung sudah dihapus atas permintaanmu. Jika ini bukan kamu, hubungi kami dengan membalas email ini.";
  return {
    subject: "Akun beOkay sudah dihapus",
    text: `Akunmu sudah dihapus\n\n${text}`,
    html: `<!doctype html><html lang="id"><body style="margin:0;background:#F6F8FA;font-family:Inter,Arial,sans-serif;color:#171B20"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px"><table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;background:#FFFFFF;border-radius:24px;padding:32px"><tr><td><p style="margin:0 0 24px;font-weight:700;font-size:18px">beOkay</p><h1 style="margin:0 0 12px;font-size:28px;line-height:1.15">Akunmu sudah dihapus</h1><p style="margin:0;font-size:16px;line-height:1.5;color:#566673">${escapeHtml(text)}</p></td></tr></table></td></tr></table></body></html>`,
  };
}

export function passwordResetEmail(url: string) {
  const intro = "Kami menerima permintaan untuk mengatur ulang kata sandi akunmu. Tautan berlaku selama 1 jam.";
  const footer = "Jika kamu tidak meminta ini, abaikan email ini. Kata sandimu tidak berubah.";
  return {
    subject: "Atur ulang kata sandi beOkay",
    text: `Atur ulang kata sandi\n\n${intro}\n\n${url}\n\n${footer}`,
    html: layout("Atur ulang kata sandi", intro, "Atur Ulang Kata Sandi", url, footer),
  };
}
