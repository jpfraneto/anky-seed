import StoreBadge from "./StoreBadge";

type StoreBadgesProps = {
  compact?: boolean;
  centered?: boolean;
};

function StoreBadges({ compact = false, centered = false }: StoreBadgesProps) {
  return (
    <div
      className={`flex flex-row gap-2 sm:gap-3 ${centered ? "items-center justify-center" : "items-center"}`}
    >
      <StoreBadge compact={compact} store="ios" />
      <StoreBadge compact={compact} store="android" />
    </div>
  );
}

export default StoreBadges;
