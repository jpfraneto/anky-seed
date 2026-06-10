import PageShell from "./PageShell";

type ComingSoonPageProps = {
  currentPath: string;
  title: string;
  onNavigate: (href: string) => void;
};

function ComingSoonPage({ currentPath, title, onNavigate }: ComingSoonPageProps) {
  return (
    <PageShell currentPath={currentPath} onNavigate={onNavigate}>
      <p className="text-xs uppercase tracking-[0.22em] text-gold-200/70">
        {title}
      </p>
      <h1 className="mt-5 font-serif text-5xl leading-tight text-cream">
        Coming soon.
      </h1>
    </PageShell>
  );
}

export default ComingSoonPage;
