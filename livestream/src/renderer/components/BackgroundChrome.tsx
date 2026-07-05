export function BackgroundChrome() {
  return (
    <div className="background-chrome" aria-hidden="true">
      <div className="chrome-scanlines" />
      <div className="chrome-vignette" />
      <div className="corner corner-tl" />
      <div className="corner corner-tr" />
      <div className="corner corner-bl" />
      <div className="corner corner-br" />
      <div className="grid-glow grid-glow-left" />
      <div className="grid-glow grid-glow-right" />
    </div>
  );
}
