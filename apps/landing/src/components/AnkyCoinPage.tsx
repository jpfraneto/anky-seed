import PageShell from "./PageShell";

type AnkyCoinPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

const ANKY_CONTRACT_ADDRESS = "0x323e74c31915db296B82b032f9665924f31EFba3";
const ANKY_DEXSCREENER_URL =
  "https://dexscreener.com/base/0x323e74c31915db296b82b032f9665924f31efba3";

const sections = [
  {
    title: "Canonical Contract",
    body: (
      <>
        The canonical $ANKY Base contract address is{" "}
        <a
          className="break-all font-mono text-gold-100 underline decoration-gold-200/45 underline-offset-4 transition hover:text-cream"
          href={ANKY_DEXSCREENER_URL}
          target="_blank"
          rel="noreferrer"
        >
          {ANKY_CONTRACT_ADDRESS}
        </a>
        . Verify this exact CA from anky.app before interacting with any token,
        pool, screenshot, or copied ticker.
      </>
    ),
  },
  {
    title: "What It Points To",
    body: "Anky is a writing practice. You sit down, you write for 8 minutes without stopping, and something emerges that your conscious mind didn't plan. The token will not change what the practice is. It will not unlock features, grant app access, replace an App Store subscription, or make the writing more real.",
  },
  {
    title: "The Memetic Layer",
    body: "$ANKY is intended as the memetic layer around the practice: a public flag for the idea that the ritual exists. The app remains usable without buying, holding, or trading any token.",
  },
  {
    title: "Verify First",
    body: "Always compare the full address before interacting with $ANKY. Nothing here is financial advice, investment advice, or an offer to buy or sell anything.",
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
