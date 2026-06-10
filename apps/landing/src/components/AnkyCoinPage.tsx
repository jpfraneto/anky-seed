import PageShell from "./PageShell";

type AnkyCoinPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

const sections = [
  {
    title: "Launch Note",
    body: "$ANKY is the memetic layer for the practice, and it serves the goal of distribution. It does not unlock or replace the practice itself.",
  },
  {
    body: "A memecoin is the simplest possible expression of an idea on the internet. No pitch deck, no roadmap, no Series A. Just a name, a ticker, and a bet that enough people will recognize what it points to.",
  },
  {
    title: "What It Points To",
    body: "Anky is a writing practice. You sit down, you write for 8 minutes without stopping, and something emerges that your conscious mind didn't plan. The token doesn't change what the practice is. It doesn't unlock features or grant access. It's a flag planted in the ground that says: this idea exists, and the market gets to decide what it's worth.",
  },
  {
    body: "The old internet released ideas through products. You built something, charged for it, and hoped people would pay. The new internet gives us the possibility to deploy ideas on the markets permissionlessly via tokens.",
  },
  {
    body: "The idea itself becomes tradeable the moment it has a name.",
  },
  {
    body: "This is either profoundly stupid or profoundly honest. Probably both. A memecoin strips away every pretension about what makes something valuable and reduces it to the only question that ever mattered: do people care about this?",
  },
  {
    body: "Most memecoins are jokes. Some jokes contain more truth than business plans. The cosmic joke of $ANKY is that a tool designed to bypass your conscious mind - to help you stop thinking and just write - now has a price feed that people watch with their conscious minds, thinking very hard about whether the number will go up or down.",
  },
  {
    body: "The mirror doesn't care about the price. The practice remains free. The app is free to download. And you can take the practice anywhere you have a pen and a timer.",
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
          Whether the token is worth a penny or a dollar, the words you wrote
          are still yours. That moment happened and it mattered because you
          matter.
        </p>
      </div>
    </PageShell>
  );
}

export default AnkyCoinPage;
