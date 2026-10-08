# App Store Connect metadata

Paste-ready listing copy for all six locales Anky ships in. Written 2026-08-27
against the live 2.0.0 listing.

```bash
./validate.rb      # every field against Apple's limits, before you paste
```

## Layout

One directory per App Store Connect localization, one file per field. This is
the `fastlane deliver` layout, so it can be automated later without moving
anything.

```
en-US/  es-MX/  fr-FR/  de-DE/  hi/  zh-Hans/
  name.txt              App Information → Name              (30)
  subtitle.txt          App Information → Subtitle          (30)
  promotional_text.txt  Version → Promotional Text          (170)
  keywords.txt          Version → Keywords                  (100)
  description.txt       Version → Description               (4000)
  release_notes.txt     Version → What's New in This Version (4000)
```

Limits are Unicode code points, which is what App Store Connect counts —
`validate.rb` counts them the same way.

## What changed from the live listing, and why

**Name** — `Anky: Writing App` → `Anky: Daily Writing Journal`. The old name
spent 17 of 30 characters and indexed only "writing" and "app". The new one
keeps the brand first and adds "daily" and "journal", the two highest-volume
terms this app can honestly claim. If you would rather not touch the name,
revert `name.txt` and nothing else changes.

**Subtitle** — `The simplest app to write.` → `Freewrite 8 minutes a day`. Same
reasoning: the old subtitle indexed nothing a person would search for. The new
one carries "freewrite" and "minutes".

**Keywords** — the field was invisible to me, so treat these as a proposal
rather than a diff. Nothing here repeats a word already in the name or
subtitle, because Apple indexes those separately and repeats are wasted
characters.

**Description** — the live one is a single 90-word paragraph. This version
keeps its voice but adds the structure the App Store's "more" fold rewards,
and says out loud what the app actually charges for. It also carries the
auto-renewable subscription disclosure Apple expects on the product page:
renewal terms, and links to the standard EULA and your privacy policy. That
block is the kind of omission that gets a review rejection, and the live
listing does not have it.

**Promotional text** — new. It sits above the description, and unlike
everything else here you can change it any time without shipping a build. Good
place for a seasonal line later.

**Release notes** — written for a polish release, honestly. If you have
specific fixes worth naming, name them; people read these.

## Before you paste — three things that need your eyes

1. **The Pro claim.** The description says writing is free and reflections are
   what you pay for, matching what the gate itself says in 2.0.0 ("Reflections
   open with the subscription. Writing is still free."). Confirm that is still
   true of the build you are shipping.
2. **The privacy policy URL.** The description links `https://anky.app/privacy-policy`.
   Confirm it resolves.
3. **The consumables.** The store sells Reflection packs (3/11/33) and Credit
   packs (22/99/421) that no document in this repo describes. The description
   refers to buying reflections "in packs" without naming tiers, which is safe
   either way, but the packs deserve their own written spec somewhere.

## Stale documents, flagged

Two files in this repo will mislead whoever reads them next:

- `docs/app-store-subscription-resubmission.md` describes 1.3.0 — a 96-day
  journey, painting levels after level 8, and an onboarding path
  ("I know." → "How does it work?" → …) that no longer exists.
- `apps/ios/Anky/Anky.storekit` lists `anky.monthly` at 9.99 and `anky.annual`
  at 88.90. The store actually sells 8.99 and 49.99, plus six consumables the
  file does not contain.

Neither is load-bearing for this metadata, but both should be corrected or
marked historical before they are trusted again.
