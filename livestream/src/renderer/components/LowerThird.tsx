import type { ShowState } from "../../state/showState";

export function LowerThird({ data }: { data: ShowState["lowerThird"] }) {
  return (
    <section className="lower-third" aria-label="Lower third">
      {data.showLogo ? (
        <div className="show-logo">
          <img src="/assets/today-anky-becomes-logo.jpeg" alt="Today Anky Becomes" />
        </div>
      ) : (
        <div className="show-logo text-logo">TODAY ANKY BECOMES</div>
      )}

      <div className="main-caption">
        <div className="caption-rule" />
        <h1>
          {data.headline.before} <span>{data.headline.highlight}</span>
          {data.headline.after ? ` ${data.headline.after}` : ""}
        </h1>

        <div className="quote-row">
          <div className="quote-mark">"</div>
          <p>
            <strong>{data.quote.speaker}:</strong> {data.quote.text}
          </p>
        </div>
      </div>

      <div className="app-cta">{data.cta}</div>
    </section>
  );
}
