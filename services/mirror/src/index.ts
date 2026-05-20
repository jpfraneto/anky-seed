import { Hono } from "hono";
import { assertProductionSafe, loadEnv } from "./env";
import { createAnkyRoute, type AnkyRouteDeps } from "./routes/anky";
import { healthRoute } from "./routes/health";
import { createSafeLogger } from "./privacy/safeLogger";
import type { DiagnosticsSink } from "./diagnostics/sink";

export function createApp(input: {
  env?: ReturnType<typeof loadEnv>;
  logger?: ReturnType<typeof createSafeLogger>;
  ankyRouteDeps?: AnkyRouteDeps;
  diagnostics?: DiagnosticsSink;
} = {}) {
  const env = input.env ?? loadEnv();
  const logger = input.logger ?? createSafeLogger();
  const app = new Hono();

  app.route("/", healthRoute);
  app.route("/", createAnkyRoute(env, logger, { ...input.ankyRouteDeps, diagnostics: input.diagnostics }));

  return app;
}

if (import.meta.main) {
  const env = loadEnv();
  assertProductionSafe(env);
  Bun.serve({
    port: env.port,
    hostname: env.host,
    fetch: createApp({ env }).fetch,
  });
  console.log(`anky mirror listening on ${env.host}:${env.port}`);
}
