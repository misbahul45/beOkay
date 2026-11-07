# syntax=docker/dockerfile:1
ARG BUN_VERSION=1.4.0

# ---- base ----
FROM oven/bun:${BUN_VERSION} AS base
WORKDIR /app

# ---- deps: semua dependency (termasuk Prisma CLI) ----
FROM base AS deps
COPY package.json bun.lock ./
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile \
    && chown -R bun:bun /app

# ---- dev: source di-bind-mount oleh compose.yaml, client di-generate saat start ----
FROM deps AS dev
ENV NODE_ENV=development HOME=/tmp
COPY --chown=bun:bun . .
EXPOSE 3000
CMD ["sh", "-c", "bun run db:generate && bun --hot index.ts"]

# ---- build: generate Prisma Client. Juga dipakai sebagai image one-shot `migrate` ----
FROM deps AS build
COPY . .
# `prisma generate` tidak membuka koneksi; URL ini hanya agar prisma.config.ts ter-resolve.
RUN DATABASE_URL=postgresql://build:build@localhost:5432/build bun run db:generate

# ---- prod-deps: hanya runtime dependency ----
FROM base AS prod-deps
COPY package.json bun.lock ./
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile --production

# ---- prod: image minimal, non-root ----
FROM base AS prod
ENV NODE_ENV=production
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/src ./src
COPY --from=build /app/index.ts /app/package.json /app/tsconfig.json ./
USER bun
EXPOSE 3000
CMD ["bun", "index.ts"]
