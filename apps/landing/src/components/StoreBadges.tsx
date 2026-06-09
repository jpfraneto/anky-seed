import StoreBadge from './StoreBadge'

type StoreBadgesProps = {
  compact?: boolean
  centered?: boolean
}

function StoreBadges({ compact = false, centered = false }: StoreBadgesProps) {
  return (
    <div className={`flex flex-col gap-3 sm:flex-row ${centered ? 'items-center justify-center' : 'items-stretch sm:items-center'}`}>
      <StoreBadge compact={compact} store="ios" />
      <StoreBadge compact={compact} store="android" />
    </div>
  )
}

export default StoreBadges
