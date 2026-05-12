export function canonicalAnkyPostMessage(input: {
  requestTime: string;
  bodySha256: string;
}): string {
  return [
    "ANKY_POST_V1",
    "method:POST",
    "path:/anky",
    `request_time:${input.requestTime}`,
    `body_sha256:${input.bodySha256}`,
  ].join("\n");
}
