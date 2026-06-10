import PageShell from "./PageShell";

type ContactPageProps = {
  currentPath: string;
  onNavigate: (href: string) => void;
};

function ContactPage({ currentPath, onNavigate }: ContactPageProps) {
  return (
    <PageShell currentPath={currentPath} onNavigate={onNavigate}>
      <p className="text-xs uppercase tracking-[0.22em] text-gold-200/70">
        Contact
      </p>
      <h1 className="mt-5 font-serif text-5xl leading-tight text-cream">
        Contact
      </h1>
      <p className="mt-7 text-lg leading-8 text-cream/74">
        If you have feedback or need support, write to{" "}
        <a
          className="break-all text-gold-100 underline decoration-gold-200/40 underline-offset-4"
          href="mailto:support@anky.app"
        >
          support@anky.app
        </a>
        .
      </p>
    </PageShell>
  );
}

export default ContactPage;
