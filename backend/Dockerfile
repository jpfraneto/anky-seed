FROM oven/bun:1.2.18

WORKDIR /app

COPY protocol ./protocol
COPY backend ./backend

WORKDIR /app/backend
RUN bun install --frozen-lockfile || bun install
RUN ln -s /app/backend/node_modules /app/protocol/implementations/typescript/node_modules
RUN bun build server.ts --target bun --external sharp --outfile dist/server.js

CMD ["bun", "dist/server.js"]
