import PageShell from "./PageShell";

type AnkyCoinPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

const sections = [
  {
    title: "Pre-Launch Note",
    body: "$ANKY is not deployed yet. When it is, the only canonical Base contract address will appear here. Until then, ignore lookalike tickers, screenshots, and copied names.",
  },
  {
    title: "What It Points To",
    body: "Anky is a writing practice. You sit down, you write for 8 minutes without stopping, and something emerges that your conscious mind didn't plan. The token will not change what the practice is. It will not unlock features, grant app access, replace credits, or make the writing more real.",
  },
  {
    title: "The Memetic Layer",
    body: "$ANKY is intended as the memetic layer around the practice: a public flag for the idea that the ritual exists. The app remains usable without buying, holding, or trading any token.",
  },
  {
    title: "Verify First",
    body: "After launch, verify the exact Base contract address from this page before interacting with any token. Nothing here is financial advice, investment advice, or an offer to buy or sell anything.",
  },
  {
    body: "The mirror does not care about the price. The practice remains free. The app is free to download. And you can take the practice anywhere you have a pen and a timer.",
  },
];

function AnkyCoinPage({ currentPath, onNavigate }: AnkyCoinPageProps) {
  return (
    <PageShell currentPath={currentPath} onNavigate={onNavigate}>
      <p className="text-xs uppercase tracking-[0.22em] text-gold-200/70">
        Memetic Layer
      </p>
      <h1 className="mt-5 font-serif text-5xl leading-tight text-cream sm:text-6xl">
        $ANKY
      </h1>

      <div className="mt-6 rounded-2xl border border-gold-200/25 bg-black/20 p-5">
        <p className="text-xs uppercase tracking-[0.2em] text-gold-200/70">
          Canonical Base Contract
        </p>
        <p className="mt-3 font-mono text-sm leading-6 text-cream/82">
          Not deployed yet. Verify on anky.app before trusting any address.
        </p>
      </div>

      <div className="mt-10 space-y-7">
        {sections.map((section, index) => (
          <section key={`${section.title ?? "note"}-${index}`}>
            {section.title ? (
              <h2 className="mb-3 font-serif text-3xl text-gold-100">
                {section.title}
              </h2>
            ) : null}
            <p className="text-lg leading-8 text-cream/74">{section.body}</p>
          </section>
        ))}
      </div>

      <div className="mt-12 border-l border-gold-200/28 pl-6">
        <p className="text-lg leading-8 text-cream/82">
          All of the containers that will come out of Anky, Inc. are just
          excuses for you to:
        </p>
        <p className="mt-5 font-serif text-4xl leading-tight text-cream">
          Write for 8 minutes and meet yourself.
        </p>
        <p className="mt-5 text-lg leading-8 text-cream/74">
          The words you wrote are still yours. That moment happened and it
          mattered because you matter.
        </p>
      </div>
    </PageShell>
  );
}

export default AnkyCoinPage;
