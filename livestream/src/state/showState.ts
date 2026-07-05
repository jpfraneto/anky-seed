export type MediaKind = "image" | "video";

export type ShowState = {
  live: boolean;
  voice: {
    origin: string;
    connected: boolean;
    lastSyncAt?: string;
    mask: VoiceMask | null;
  };
  caption: {
    speaker?: string;
    text: string;
    updatedAt?: string;
  };
  clocks: {
    left: ClockState;
    right: ClockState;
  };
  host: {
    name: string;
    source: "camera" | "obs" | "video";
    src?: string;
  };
  center: MediaState & {
    caption: string;
  };
  guest: MediaState & {
    title: string;
  };
  lowerThird: {
    showLogo: boolean;
    headline: {
      before: string;
      highlight: string;
      after: string;
    };
    quote: {
      speaker: string;
      text: string;
    };
    cta: string;
  };
  ticker: Array<{
    icon: string;
    symbol: string;
    label?: string;
  }>;
};

export type ClockState = {
  label: string;
  timeZone: string;
};

export type MediaState = {
  kind: MediaKind;
  src: string;
};

export type VoiceMask = {
  key: string;
  name: string;
  title: string;
  subtitle: string;
  label: string;
  image: string;
  invocation: string;
  format: string;
};

export type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends Array<infer U>
    ? Array<DeepPartial<U>>
    : T[P] extends object
      ? DeepPartial<T[P]>
      : T[P];
};
