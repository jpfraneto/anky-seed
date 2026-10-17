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

## Version 2.2.0 — "the simplest writing app" (2026-10-16)

The app went fully offline: no server, no AI reflections, no subscription.
Everything in the listing that described those is gone.

- **Subtitle:** "The simplest writing app" in every locale (was "Freewrite 8
  minutes a day" — duration is now 1–8 minutes or ∞).
- **Promotional text / description:** lead with the one page, the clock, the
  8 second rule and "tap to keep writing"; say plainly that nothing leaves the
  phone; drop Anky Pro, reflections, recording and the subscription legalese
  (there are no purchases left to disclose). Privacy and Terms links point at
  each locale's anky.app page.
- **Name and keywords:** unchanged except en-US keywords: "stream,consciousness" became "freewrite,minimal,calm".
- **Release notes:** what a 2.1 user will notice.
- **review_notes.txt:** rewritten for 2.2.0 (69).
- **App Privacy:** answer "Data Not Collected" — see `../NUTRITION_LABEL.md`.
- **In-app purchases:** Anky Pro monthly/yearly must be removed from sale in
  App Store Connect by hand; nothing in the app sells them anymore.
