export type SafeLogFields = {
  requestId: string;
  publicKeyHash?: string;
  ankyHash?: string;
  client?: string;
  statusCode: number;
  latencyMs: number;
  modelProvider?: "openrouter" | "mock" | "none";
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
