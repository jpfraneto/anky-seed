export type SafeLogFields = {
  requestId: string;
  publicKeyHash?: string;
  ankyHash?: string;
  client?: string;
  appVersion?: string;
  durationMs?: number;
  statusCode: number;
  latencyMs: number;
  modelProvider?: "openrouter" | "mock" | "none";
  modelFailure?: string;
  creditResult?: string;
};

export type SafeLogger = {
  info(fields: SafeLogFields): void;
};

export function createSafeLogger(sink: Pick<Console, "log"> = console): SafeLogger {
  return {
    info(fields) {
      sink.log(JSON.stringify(fields));
    },
  };
}
