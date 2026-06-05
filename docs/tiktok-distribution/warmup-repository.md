# Anky TikTok Warmup Repository

Status: living operating document

Purpose: build a curated repository of TikTok videos that a new Anky account can watch, save, and occasionally comment on so its For You feed learns the right neighborhood: people done seeking, constraint-ready writers, anti-performance critique, and privacy-aware people who will understand a local-first mirror practice.

Use [strategy.md](/Users/kithkui/anky/docs/tiktok-distribution/strategy.md) as the strategic canon. This file is the operating manual for collecting exact videos.

This is not an automation plan. Use it as a manual curation system for a real account operated with judgment. Do not mass-like, mass-comment, scrape private content, or pretend to be a person other than the account operator.

## The Repository Shape

Use [watchlist.csv](/Users/kithkui/anky/docs/tiktok-distribution/watchlist.csv) as the canonical queue.

Current validated snapshot, 2026-06-05:

- 888 exact TikTok video URLs.
- 888 unique video URLs.
- 0 malformed CSV rows.
- 0 duplicate video URLs.
- 0 malformed TikTok video URLs.

Every row is either:

- `search`: a TikTok search query that should produce candidate videos.
- `creator`: a profile or known creator account to review manually.
- `video`: an individual video that has been accepted into the warmup queue.

Promote rows from `search` or `creator` into `video` rows only after watching enough of the visible content to classify it. Do not invent captions, claims, creator intent, or video metadata.

## Acceptance Rule

A video belongs in the queue if it does at least one of these:

- Speaks directly to the seeker trap: seeking as identity, understanding as avoidance, path as hiding place.
- Shows serious direct-path, Advaita, Zen, meditation, Buddhist, Jungian, grief, death, or existential inquiry without becoming spiritual entertainment.
- Critiques spiritual ego, guru culture, manifestation toxicity, or self-improvement performance.
- Bridges into the actual product mechanism: forward-only writing, no editing, no backspace, blank page fear, creative blocks, perfectionism, raw first drafts, stream-of-consciousness writing, or the editor/controller getting tired.
- Builds trust in the transient mirror: local-first software, privacy-preserving AI, AI that does not remember, data ownership, or discomfort with cloud journals and AI companions.
- Lightly bridges into story, parenting, or symbol only when the video points back to raw writing, reflection, or unconscious material instead of generic parenting/story content.
- Creates a natural place for an Anky-style comment that is precise, non-promotional, and not performatively wise.

Reject the video if the main energy is:

- Law of attraction, wealth manifestation, twin flames, chosen-one content, aura/tarot/numerology/astrology entertainment, crystal healing, generic chakra content, hustle spirituality, wellness influencer branding, or broad motivational self-improvement.
- A creator using spiritual language mostly to gather followers, sell identity, sell certainty, or perform enlightenment.
- Generic journaling productivity, generic parenting advice, AI companion, AI girlfriend, cloud journal, or habit tracker content that trains the account away from Anky's protected ritual.
- Content where Anky would sound like a brand trying to enter the room.

Exception: critique videos about those spaces may be accepted when the critique is sober and precise.

## Warmup Ratios

Use these as weekly proportions, not hard daily quotas.

- Ring 1 direct-path / post-seeking: 38%
- Product constraint / raw writing / creative excavation: 24%
- Anti-performance / marketplace critique: 18%
- Serious practice fatigue / meditation depth: 10%
- Transient mirror / local-first / privacy-aware AI: 7%
- Story, symbol, and parenting-as-mirror: 3%

The account should feel like a witness with a protected writing ritual underneath, not like a generic spirituality account, writing account, parenting account, or AI product account.

## Watch Session Protocol

1. Open 5 to 12 candidate videos from the current queue.
2. Watch the full video only when it is relevant. Skip quickly when it drifts into avoid categories.
3. Save videos that are excellent examples of the neighborhood.
4. Like sparingly, only when the content genuinely fits.
5. Comment rarely. A good target rate is one comment for every 8 to 20 watched videos.
6. Follow a creator only after at least three of their videos fit the Anky neighborhood.
7. After each session, update row status: `candidate`, `accepted`, `watched`, `saved`, `commented`, `rejected`, or `needs_review`.

## Populating Exact Video URLs

The seed queue starts with search URLs because TikTok recommendations are account-specific. After the new account is logged in, use the in-app browser or Chrome session to turn search rows into exact `video` rows.

For each accepted video:

1. Copy the TikTok video URL.
2. Add a new row with `entry_type=video`.
3. Fill `source_url`, `creator_handle`, `visible_hook`, `why_it_fits`, `watch_action`, and `comment_direction`.
4. Leave metrics approximate and timestamped if they are useful; TikTok counts move quickly.
5. Keep the original `search` row. It remains a discovery source.

Do not bulk collect videos just because they match a keyword. The repository is valuable only if each accepted video has a clear reason for training the account toward Anky's audience.

## Commenting Rule

The best Anky comment should make the room quieter.

Never comment:

- "check out Anky"
- "we built an app for this"
- "link in bio"
- "this is so true"
- "as a brand"
- anything that sounds like a teacher recruiting students

Use [comment-bank.csv](/Users/kithkui/anky/docs/tiktok-distribution/comment-bank.csv) as raw material, then write the exact sentence for the video in front of you.

## Classifying A Video

Required fields for accepted `video` rows:

- `entry_type`: `video`
- `status`: `accepted`, `watched`, `saved`, or `commented`
- `ring`: `ring_1`, `ring_2`, `ring_3`, `ring_4`, or `avoid`
- `pillar`: one of `seeker_trap`, `constraint_mechanism`, `mirror_mechanism`, `transient_mirror`, `anti_performance`, `child_story_bridge`, `story_symbol_bridge`, `founder_confession`, `practice_fatigue`, `creative_excavation`, `parenting_mirror`, `marketplace_critique`
- `source_url`: TikTok video URL
- `visible_hook`: visible opening text, spoken hook, or concise description
- `why_it_fits`: one sentence explaining the fit
- `watch_action`: `watch_full`, `rewatch`, `save`, `comment`, `follow_creator`, or `skip`
- `comment_direction`: the kind of sentence Anky could leave

Optional but useful:

- `creator_handle`
- `creator_name`
- `region`
- `language`
- `duration_seconds`
- `observed_likes`
- `observed_comments`
- `sound_or_topic`
- `risk_notes`

## Discovery Keywords

Start with these searches before relying on For You:

- `seeker trap`
- `tired of seeking`
- `spiritual seeker`
- `nonduality`
- `advaita`
- `Ramana Maharshi`
- `Nisargadatta`
- `I Am That`
- `Rupert Spira`
- `Francis Lucille`
- `Swami Sarvapriyananda`
- `Who am I self inquiry`
- `pathless path`
- `spiritual ego`
- `spiritual bypassing`
- `guru culture`
- `manifestation critique`
- `meditation retreat integration`
- `dark night meditation`
- `Jung shadow work`
- `no backspace writing`
- `write without editing`
- `stream of consciousness writing`
- `first draft writing`
- `blank page fear`
- `creative perfectionism`
- `over editing writing`
- `perfectionism artist`
- `raw writing process`
- `writing as healing`
- `writing as prayer`
- `unconscious writing`
- `artist process truth`
- `local first software`
- `private journaling app`
- `AI privacy`
- `AI memory concerns`
- `cloud journal privacy`
- `parenting triggers`
- `child as mirror`
- `bedtime story meaning`

When TikTok starts recommending the right neighborhood, add the exact video URLs into the repository. The first durable asset is not the search list. It is the accepted-video queue.

## Review Cadence

At the end of each week:

- Remove rows that trained the feed toward spiritual entertainment.
- Promote the best `watched` videos into `saved`.
- Identify creators with three or more accepted videos.
- Extract the comments that received thoughtful replies.
- Add new search terms from the language TikTok is actually surfacing.

The standard is not "did this get engagement?"

The standard is:

> Did this make the account more likely to find people done seeking?
