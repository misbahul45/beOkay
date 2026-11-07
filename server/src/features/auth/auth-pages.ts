const STYLE = `
:root{color-scheme:light}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#C8D9E8;font-family:Inter,system-ui,-apple-system,Arial,sans-serif;color:#171B20}
main{width:min(440px,100% - 32px);background:#F6F8FA;border-radius:28px;padding:32px 28px}
.brand{font-weight:700;font-size:18px;margin:0 0 28px}
h1{font-size:30px;line-height:1.12;margin:0 0 12px;letter-spacing:-.4px}
p{font-size:16px;line-height:1.5;color:#566673;margin:0 0 20px}
label{display:block;font-size:14px;font-weight:600;margin:0 0 6px}
input{width:100%;height:52px;border:1px solid #E1E8EE;border-radius:16px;padding:0 16px;font-size:16px;background:#fff;color:#171B20;margin:0 0 16px}
input:focus-visible,button:focus-visible{outline:3px solid #171B20;outline-offset:2px}
button{width:100%;height:52px;border:0;border-radius:999px;background:#171B20;color:#fff;font-size:16px;font-weight:600;cursor:pointer}
button[disabled]{opacity:.6;cursor:default}
.msg{min-height:24px;font-size:14px;margin:12px 0 0}
.msg.error{color:#8A3B35}
.msg.ok{color:#171B20}
`;

function page(title: string, body: string, script?: string): Response {
  const nonce = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));
  const csp = [
    "default-src 'none'",
    `style-src 'nonce-${nonce}'`,
    `script-src 'nonce-${nonce}'`,
    "connect-src 'self'",
    "form-action 'none'",
    "base-uri 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
  const html = `<!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${title}</title><style nonce="${nonce}">${STYLE}</style></head><body><main><p class="brand">beOkay</p>${body}</main>${script ? `<script nonce="${nonce}">${script}</script>` : ""}</body></html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp },
  });
}

export function verifiedPage(failed: boolean): Response {
  if (failed) {
    return page(
      "Tautan tidak berlaku",
      `<h1>Tautan tidak berlaku.</h1><p>Tautan verifikasi sudah kedaluwarsa atau pernah dipakai. Buka aplikasi beOkay lalu minta tautan baru.</p>`,
    );
  }
  return page(
    "Email terverifikasi",
    `<h1>Email terverifikasi.</h1><p>Akunmu sudah aman. Kembali ke aplikasi beOkay lalu masuk dengan email dan kata sandimu.</p>`,
  );
}

const RESET_SCRIPT = `
const params = new URLSearchParams(location.search);
const token = params.get("token");
history.replaceState(null, "", location.pathname);
const form = document.getElementById("form");
const msg = document.getElementById("msg");
const submit = document.getElementById("submit");
const show = (text, kind) => { msg.textContent = text; msg.className = "msg " + kind; };
if (!token) {
  form.hidden = true;
  show("Tautan tidak lengkap. Minta tautan baru dari aplikasi beOkay.", "error");
}
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const password = document.getElementById("password").value;
  const confirm = document.getElementById("confirm").value;
  if (password.length < 10) return show("Kata sandi minimal 10 karakter.", "error");
  if (password !== confirm) return show("Konfirmasi kata sandi belum sama.", "error");
  submit.disabled = true;
  show("Menyimpan...", "ok");
  try {
    const response = await fetch("/api/auth/reset-password", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ newPassword: password, token }),
    });
    if (response.ok) {
      form.hidden = true;
      show("Kata sandi diperbarui. Kembali ke aplikasi beOkay lalu masuk dengan kata sandi barumu.", "ok");
    } else {
      submit.disabled = false;
      show("Tautan tidak berlaku atau kata sandi tidak memenuhi syarat. Coba minta tautan baru.", "error");
    }
  } catch {
    submit.disabled = false;
    show("Tidak bisa terhubung. Periksa koneksimu lalu coba lagi.", "error");
  }
});
`;

export function resetPasswordPage(): Response {
  return page(
    "Atur ulang kata sandi",
    `<h1>Atur ulang kata sandi.</h1><p>Pilih kata sandi baru minimal 10 karakter.</p><form id="form" novalidate><label for="password">Kata sandi baru</label><input id="password" type="password" autocomplete="new-password" required minlength="10"><label for="confirm">Ulangi kata sandi</label><input id="confirm" type="password" autocomplete="new-password" required minlength="10"><button id="submit" type="submit">Simpan Kata Sandi</button></form><p id="msg" class="msg" role="status" aria-live="polite"></p>`,
    RESET_SCRIPT,
  );
}
