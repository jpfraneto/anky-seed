const apiOrigin =
  import.meta.env.VITE_SHOW_STATE_ORIGIN ??
  `${window.location.protocol}//${window.location.hostname}:8787`;

export const stateApi = {
  origin: apiOrigin,
  stateUrl: `${apiOrigin}/state`,
  patchUrl: `${apiOrigin}/patch`,
  wsUrl: `${apiOrigin.replace(/^http/, "ws")}/ws`,
};
