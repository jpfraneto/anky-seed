import { useEffect, useRef, useState } from "react";
import type { ShowState } from "../../state/showState";

export function HostSlot({ host }: { host: ShowState["host"] }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [cameraFailed, setCameraFailed] = useState(false);

  useEffect(() => {
    if (host.source !== "camera") {
      return;
    }

    let stream: MediaStream | undefined;

    async function startCamera() {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: {
            width: 1280,
            height: 720,
          },
          audio: false,
        });

        if (videoRef.current) {
          videoRef.current.srcObject = stream;
        }
      } catch {
        setCameraFailed(true);
      }
    }

    startCamera();

    return () => {
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, [host.source]);

  return (
    <article className={`host-card ${host.source === "obs" ? "transparent-slot" : ""}`}>
      <div className="panel-frame" />
      {host.source === "camera" && !cameraFailed ? (
        <video ref={videoRef} autoPlay muted playsInline />
      ) : host.source === "video" && host.src ? (
        <video src={host.src} autoPlay muted loop playsInline />
      ) : (
        <div className="obs-hole" />
      )}
      <div className="slot-name">{host.name}</div>
      <div className="slot-kind">{host.source.toUpperCase()}</div>
    </article>
  );
}
