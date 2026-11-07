@AGENTS.md

## Khusus Claude Code
- **Tidak boleh commit atau push dalam kondisi apa pun**, meski diminta secara implisit ("simpan", "selesaikan"). Bila pengguna ingin commit, beri tahu perintahnya dan biarkan mereka yang menjalankan.
- Deny rule di `.claude/settings.json` adalah pagar pengaman; jangan mencoba menyiasatinya (mis. `git -C`, alias, script pembungkus).
- Desain: kerjakan di Figma lewat MCP `figcraft` sebelum menulis UI. Bila `figcraft` gagal terhubung, laporkan ke pengguna, jangan diganti dengan mockup lain tanpa persetujuan.
