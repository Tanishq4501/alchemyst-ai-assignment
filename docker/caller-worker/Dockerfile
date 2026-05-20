# ── Stage 1: install production dependencies ──────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

# ── Stage 2: runtime image ────────────────────────────────────────────────────
FROM node:20-alpine
WORKDIR /app

# tsx is needed for runtime TypeScript transpilation
RUN npm install -g tsx@4

COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY src/ ./src/

ENV NODE_ENV=production

# III_URL is injected at runtime by the startup script / docker run -e
CMD ["tsx", "src/worker.ts"]
