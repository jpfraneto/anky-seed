export type MirrorDiagnosticEvent = {
  requestId: string;
  addressHash?: string;
  ankyHash?: string;
  client?: "ios" | "android" | "other";
  identityVersion?: string;
  chainId?: number;
  status: number;
  provider?: string;
  durationMs?: number;
  errorCode?: string;
  startedAt: string;
  finishedAt: string;
};

export interface DiagnosticsSink {
  record(event: MirrorDiagnosticEvent): void | Promise<void>;
}

export class ConsoleDiagnosticsSink implements DiagnosticsSink {
  constructor(private readonly sink: Pick<Console, "log"> = console) {}

  record(event: MirrorDiagnosticEvent): void {
    this.sink.log(JSON.stringify(event));
  }
}
