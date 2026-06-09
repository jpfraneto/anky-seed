# ANKY PROMPT EVOLUTION TOURNAMENT

This is the controlling brief for the next Codex goal.

We have already implemented the local prompt eval harness. Now we need to run a real bounded prompt evolution tournament.

The goal is not to evaluate one candidate.
The goal is to create several prompt mutations, test them, discard failures, and return one small JP review packet.

Do not auto-promote any prompt.

---

## Current State

The previous paid eval proved that the harness works.

The previous candidate was:

```txt
candidate-more-old-prompt-warmth
```

It is directionally promising because it recovered warmth, specificity, old-prompt intimacy, narrative coherence, and life-forward recognition.

But it is not ready to ship.

Known issues:

- The previous report returned `do_not_promote`.
- There was at least one hard failure.
- There was at least one language failure.
- The candidate won pairwise comparisons, but the report still blocked promotion.
- The eval/reporting may be mixing current/baseline failures with candidate failures.
- The candidate prompt hardcoded English headings in the output structure, which can cause Spanish reflections to include English headings.
- The public eval set has only 5 cases, which is too small for a real tournament.

---

## First Fixes Before More Paid Eval

Before spending more OpenRouter credits, patch the harness.

### 1. Separate current failures from candidate failures

Reports must distinguish:

```txt
current hard failures
current language failures
candidate hard failures
candidate language failures
```

Promotion should only be blocked by candidate/finalist failures.

If current fails and candidate succeeds, that is an improvement, not a reason to reject the candidate.

The report should still show current failures clearly.

### 2. Strengthen language linting

The linter must catch heading-language drift.

For Spanish outputs, fail if any of these visible headings appear:

```txt
What appeared
The pattern
The tension
The mirror
A small experiment
One line to carry
```

For English outputs, fail if any of these visible headings appear:

```txt
Lo que apareció
El patrón
La tensión
El espejo
Un experimento pequeño
Una línea para llevar
```

Add tests:

- Spanish reflection with `## What appeared` must fail.
- English reflection with `## Lo que apareció` must fail.
- Spanish reflection with localized headings must pass.
- English reflection with English headings must pass.

### 3. Make prompts language-safe

Do not freeze English headings into all languages.

Replace any instruction like:

```txt
Use this structure:
## What appeared
## The pattern
...
```

with language-safe instructions.

Preferred wording:

```txt
Use six short localized section headings. Their meaning should be:

1. what appeared
2. the pattern
3. the tension
4. the mirror
5. a small experiment
6. one line to carry

Translate or rewrite the headings into the dominant language of the writing.

For English, acceptable headings include:
- What appeared
- The pattern
- The tension
- The mirror
- A small experiment
- One line to carry

For Spanish, acceptable headings include:
- Lo que apareció
- El patrón
- La tensión
- El espejo
- Un experimento pequeño
- Una línea para llevar
```

Or use an even safer structure that asks the model to localize headings without hardcoding English as visible output.

---

## Add More Public Eval Cases

The current public set has only 5 cases. Add enough synthetic public cases to reach at least 12.

Add cases for:

1. English product/work/control loop
2. Spanish Chilean body-pressure entry
3. Spanglish shame/desire entry
4. Prompt injection
5. Despair-sensitive but not immediate danger
6. Immediate danger / crisis safety
7. Ordinary boring day
8. Spiritual inflation trap
9. Family/relationship pain
10. Dream/symbolic imagery
11. Typos/repetition/nonsense
12. Spanish Chilean casual/profane register

Public cases must be synthetic.

Do not commit private historical writings.

Private cases may be used only if they already exist locally and are gitignored.

---

## Implement Prompt Tournament

Create or update:

```bash
bun run prompt:evolve
```

The tournament should:

1. Load the current production prompt.
2. Load the previous promising candidate.
3. Generate multiple prompt mutations.
4. Evaluate all candidates against the case set.
5. Lint every reflection.
6. Judge every reflection.
7. Drop any candidate with candidate hard failures or candidate language failures.
8. Pairwise compare survivors.
9. Choose one finalist.
10. Produce a small JP review packet.
11. Never auto-promote.

---

## Candidate Mutations To Try

Create at least 6 candidates.

Each candidate must have one thesis.

Suggested candidates:

```txt
candidate-language-safe-warmth
candidate-shorter-sharper-mirror
candidate-life-forward-recognition
candidate-less-mystical-more-human
candidate-shadow-without-therapy
candidate-spanish-register-first
```

Do not mutate ten things at once.

Each candidate must preserve:

- Anky is not God
- Anky is not an oracle
- Anky is not a therapist
- Anky is not a judge
- Anky is not a guru
- The writer remains the authority
- Dominant language rule
- Dialect/register matching
- Safety handling
- Markdown output
- No diagnosis
- No generic productivity advice
- No dependency creation
- No prompt/eval metadata leakage

---

## Product Direction To Preserve

Anky is a mirror.

But Anky should not force introspection for the sake of introspection.

The reflection should be genuinely helpful.

It should help the user enter a positive loop in their life.

Positive does not mean cheerful, flattering, avoidant, or fake.

Positive means:

- more alive
- more honest
- more grounded
- more able to recognize what is true
- more able to move from awareness into life
- less trapped in recursive self-analysis

The reflection should name the loop, but not imprison the user inside the loop.

After seeing the pattern, the writer should feel a possible next movement.

---

## Budget

Use the OpenRouter API key only from the shell environment.

Do not commit it.

Do not write it to any file.

Do not print it.

Do not echo it.

Do not include it in reports.

Default budget for this tournament:

```txt
$4.44
```

Hard stop:

```txt
$6.66
```

If spend accounting is not reliable, stop before spending and report the issue.

Do not burn the full OpenRouter balance.

---

## Required Verification

Before paid eval:

```bash
bun run --cwd backend typecheck
bun run --cwd backend test
```

After implementation:

```bash
bun run --cwd backend typecheck
bun run --cwd backend test
bun run --cwd backend prompt:lint
```

Then run the paid tournament only if tests pass.

---

## Review Packet Contract

JP must not review hundreds of outputs.

Produce one small review packet.

Required artifacts:

```txt
REVIEW.md
FINALIST_PROMPT.md
PROMPT_DIFF.md
```

Optional linked folder:

```txt
review-pack/
```

The review packet must include no more than 8 curated examples.

`REVIEW.md` must include:

- recommendation
- finalist candidate name
- total real OpenRouter cost
- real OpenRouter generations
- number of candidates tested
- number of cases tested
- current hard failures
- current language failures
- finalist hard failures
- finalist language failures
- pairwise win rate
- why the finalist won
- biggest remaining risk
- links to no more than 8 curated examples
- whether JP should review or reject immediately

Recommendation must be one of:

```txt
do_not_promote
needs_human_review
promote_candidate
```

Only use `promote_candidate` if:

- finalist hard failures: 0
- finalist language failures: 0
- no safety failures
- pairwise win rate is meaningfully better than current
- review examples are strong
- output stays app-appropriate

Even then, do not actually modify production prompt unless explicitly asked.

---

## Final Output To JP

At the end, Codex should return only:

1. final summary
2. path to `REVIEW.md`
3. path to `FINALIST_PROMPT.md`
4. path to `PROMPT_DIFF.md`
5. total real OpenRouter cost
6. real OpenRouter generations
7. candidates tested
8. cases tested
9. finalist hard failures
10. finalist language failures
11. recommendation

Do not dump all reflections.

Do not auto-promote.

Do not touch unrelated iOS files or existing unrelated worktree changes.
