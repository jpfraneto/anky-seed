FROM oven/bun:1

WORKDIR /app

COPY protocol ./protocol
COPY services/mirror ./services/mirror

WORKDIR /app/services/mirror
RUN bun install --frozen-lockfile || bun install

ENV NODE_ENV=production
CMD ["bun", "run", "start"]
