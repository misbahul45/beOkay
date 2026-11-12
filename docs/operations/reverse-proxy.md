# Reverse proxy untuk API beOkay

> Sejak 3.0 Fase 9 (S-10). API mendengarkan HTTP di `127.0.0.1:3000` (`compose.prod.yaml`). TLS dan HSTS dipasang di proxy. API sendiri sudah mengirim `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Cross-Origin-Resource-Policy`, `Permissions-Policy`, `Cache-Control: no-store` untuk `/api/*` dan `/s/*`, serta `Strict-Transport-Security` saat `NODE_ENV=production`. Proxy tidak perlu menambah header yang sama dua kali.

Syarat:

- `TRUST_PROXY=true` agar alamat klien untuk batas laju berasal dari `X-Forwarded-For` proxy ini saja.
- Teruskan `Upgrade`/`Connection` untuk `/api/me/realtime` (WebSocket) dengan idle timeout > 120 dtk.
- Batasi badan permintaan ≤ 6 MB (unggah foto makanan); API menolak JSON > 64 KB sendiri.
- Jangan teruskan `/metrics` ke internet; biarkan hanya dari jaringan internal atau pemantau.

## Caddy

```caddyfile
api.contoh.id {
	encode zstd gzip
	request_body {
		max_size 6MB
	}
	@metrics path /metrics
	respond @metrics 404
	reverse_proxy 127.0.0.1:3000 {
		header_up X-Forwarded-Proto {scheme}
		transport http {
			read_timeout 130s
		}
	}
	header {
		-Server
	}
}
```

Caddy menangani sertifikat dan meneruskan WebSocket secara otomatis.

## nginx

```nginx
server {
    listen 443 ssl http2;
    server_name api.contoh.id;
    ssl_certificate     /etc/letsencrypt/live/api.contoh.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.contoh.id/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 6m;
    server_tokens off;

    location = /metrics { return 404; }

    location /api/me/realtime {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_read_timeout 130s;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 80;
    server_name api.contoh.id;
    return 301 https://$host$request_uri;
}
```

`X-Forwarded-For $remote_addr` (bukan `$proxy_add_x_forwarded_for`) mencegah klien menyisipkan alamat palsu ke batas laju.
