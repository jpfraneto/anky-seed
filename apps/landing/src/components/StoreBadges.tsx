import StoreBadge from "./StoreBadge";

type StoreBadgesProps = {
  compact?: boolean;
  centered?: boolean;
  locale?: "en" | "es";
};

function StoreBadges({
  compact = false,
  centered = false,
  locale = "en",
}: StoreBadgesProps) {
  return (
    <div
      className={`flex flex-row gap-2 sm:gap-3 ${centered ? "items-center justify-center" : "items-center"}`}
    >
      <StoreBadge compact={compact} locale={locale} store="ios" />
      <StoreBadge compact={compact} locale={locale} store="android" />
    </div>
  );
}

export default StoreBadges;
