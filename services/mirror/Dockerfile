FROM oven/bun:1.2.18

WORKDIR /app

COPY protocol ./protocol
COPY services/mirror ./services/mirror

WORKDIR /app/services/mirror
RUN bun install --frozen-lockfile || bun install
RUN ln -s /app/services/mirror/node_modules /app/protocol/implementations/typescript/node_modules
RUN bun build src/index.ts --target bun --outfile dist/index.js

ENV NODE_ENV=production
CMD ["bun", "dist/index.js"]
