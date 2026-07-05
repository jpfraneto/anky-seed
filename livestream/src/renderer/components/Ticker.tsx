import type { ShowState } from "../../state/showState";

export function Ticker({ items }: { items: ShowState["ticker"] }) {
  const doubled = [...items, ...items, ...items];

  return (
    <footer className="ticker" aria-label="Ticker">
      <div className="ticker-label">HOT MEMES</div>

      <div className="ticker-window">
        <div className="ticker-track">
          {doubled.map((item, index) => (
            <div className="ticker-item" key={`${item.symbol}-${index}`}>
              <img src={item.icon} alt="" />
              <span>{item.symbol}</span>
              {item.label ? <small>{item.label}</small> : null}
            </div>
          ))}
        </div>
      </div>
    </footer>
  );
}
