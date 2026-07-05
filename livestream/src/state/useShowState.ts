import { useEffect, useState } from "react";
import { deepMerge } from "./deepMerge";
import { defaultShowState } from "./defaultState";
import { stateApi } from "./stateClient";
import type { DeepPartial, ShowState } from "./showState";

type ServerMessage =
  | { type: "state.full"; state: ShowState }
  | { type: "state.patch"; patch: DeepPartial<ShowState>; state?: ShowState };

export function useShowState() {
  const [state, setState] = useState(defaultShowState);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    let closed = false;
    let retryId: number | undefined;
    let socket: WebSocket | undefined;

    fetch(stateApi.stateUrl)
      .then((res) => (res.ok ? res.json() : Promise.reject(res.statusText)))
      .then((nextState: ShowState) => {
        if (!closed) {
          setState(nextState);
        }
      })
      .catch(() => {
        if (!closed) {
          setState(defaultShowState);
        }
      });

    function connect() {
      socket = new WebSocket(stateApi.wsUrl);

      socket.addEventListener("open", () => {
        setConnected(true);
      });

      socket.addEventListener("message", (event) => {
        const message = JSON.parse(event.data) as ServerMessage;

        if (message.type === "state.full") {
          setState(message.state);
          return;
        }

        if (message.state) {
          setState(message.state);
          return;
        }

        setState((current) => deepMerge(current, message.patch));
      });

      socket.addEventListener("close", () => {
        setConnected(false);

        if (!closed) {
          retryId = window.setTimeout(connect, 1200);
        }
      });

      socket.addEventListener("error", () => {
        socket?.close();
      });
    }

    connect();

    return () => {
      closed = true;
      window.clearTimeout(retryId);
      socket?.close();
    };
  }, []);

  return { state, connected };
}
