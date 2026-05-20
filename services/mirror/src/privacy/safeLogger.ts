export type SafeLogFields = {
  requestId: string;
  addressHash?: string;
  accountIdHash?: string;
  ankyHash?: string;
  client?: string;
  appVersion?: string;
  durationMs?: number;
  identityVersion?: string;
  chainId?: number;
  statusCode: number;
  latencyMs: number;
  modelProvider?: string;
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
