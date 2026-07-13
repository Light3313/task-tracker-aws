# ── builder ──
FROM node:24-alpine3.24 AS builder
WORKDIR /app

RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm build

# ── runner ──
FROM node:24-alpine3.24 AS runner

WORKDIR /app

COPY --chown=node:node --from=builder /app/.next/standalone ./
COPY --chown=node:node --from=builder /app/.next/static    ./.next/static

RUN rm -rf /usr/local/lib/node_modules/npm \
           /usr/local/bin/npm /usr/local/bin/npx
           
EXPOSE 3000
ENV HOSTNAME=0.0.0.0

USER node

CMD [ "node", "server.js" ]