import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BroadcastScene } from "./renderer/BroadcastScene";
import { ControlPanel } from "./control/ControlPanel";
import "./styles.css";

function App() {
  const path = window.location.pathname;

  if (path.startsWith("/control")) {
    return <ControlPanel />;
  }

  return <BroadcastScene />;
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
