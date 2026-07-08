// -----------------------------------------------------------------------------
// One-time seeding of the shared static default paintings (levels 2–8).
//
// Each level's seed text is a written stream of consciousness whose weather the
// distiller turns into that painting's scene. The seven texts walk the seven
// kingdoms above the first (level 1, "The Door", ships bundled with the app and
// already glimpses the ember kingdom's volcano): fire, harvest, heart, voice,
// night-sight, clarity, creation — the same arc a writer walks into the
// practice. Kingdom names never appear: not in the app, not in these texts.
//
// Usage:
//   ANKY_ADMIN_KEY=... bun scripts/seed-default-paintings.ts [--distill-only] [--level N]
//   ANKY_BASE_URL overrides the production default.
// -----------------------------------------------------------------------------

const BASE_URL = process.env.ANKY_BASE_URL ?? "https://mirror-production-a23c.up.railway.app";
const ADMIN_KEY = process.env.ANKY_ADMIN_KEY ?? "";

const SEED_TEXTS: Record<number, string> = {
  2: `okay second time here and i can feel my heart going faster than my hands, there is something under the surface today, like coals under ash. i keep circling the same wanting and not naming it. all day i scroll and scroll and it is like eating smoke, and then i sit here and there is actual fire, small, but mine. i remember standing at the edge of a canyon at dusk once, everything orange, the rocks holding the day's heat long after the sun went down — that is what this feels like, heat kept in the body. marigolds on the windowsill. i keep thinking of embers, how you blow on them and they answer. i don't want comfort, i want heat. the wanting is not a problem, the wanting is the engine, and i have spent years apologizing for it and i am done apologizing. blow on the coals. let it catch. there is a dance in me that has been waiting a long time for the music to start, and maybe the music was always just this, fingers moving, sparks going up into a warm dark sky.`,

  3: `third day and the trick is just to show up, that is the whole secret nobody wants: you come back to the field every morning and you work it again. i think about wheat a lot lately, how it doesn't hurry, how a field turns gold one ordinary day at a time. bread rising somewhere, the smell of it, work that feeds. i used to think discipline was a cage and now i think it is a sun you plant things under. every sentence i put down is a seed i will not see sprout today and that is fine — harvest is not the point, tending is the point. tall slender trees at the edge of the field standing like they have somewhere to be and refuse to go; i want that kind of standing. golden hour makes even the dust look holy. my hands are learning the weight of the work. come back tomorrow. come back the day after. stack the days like sheaves. the sun does not negotiate and neither should i: rise, write, rest, repeat, and one morning you look up and the whole field is gold.`,

  4: `something softened today. i wrote hard things yesterday and woke up lighter, like rain had passed through in the night. everything is green when i close my eyes — moss on the north side of old stones, a meadow after rain, white blossoms letting go of the branch without any grief at all. i have been so hard on myself for so long, grading every day like an exam. what if the heart just opens the way an orchard blooms, not because it earned the spring but because the spring came. tenderness might be a strength: the softest grass survives the storm that snaps the proud trees. petals on wet grass. a small stream somewhere i can hear but not see. i forgive the years i spent asleep, i forgive the versions of me that didn't know better — they were doing their best with the light they had. the chest is not a fist anymore, it is a field, and things are growing in it that i did not plant. kindness coming up like clover, everywhere, uninvited, welcome.`,

  5: `there is a river under the words and today i can hear it. all my life i said the acceptable thing, the polished thing, and the true thing stayed in the throat like a stone. but water finds a way, it always finds a way — around the stone, over it, wearing it smooth. i write and the current pulls. pale slender birches leaning over blue water, waterfalls that do not apologize for their volume. the voice is not made, it is found; it was here the whole time under the ice, i just had to stop performing long enough to listen. say the true sentence. then the next one. the river doesn't rehearse. i want to speak the way water speaks — continuously, honestly, downhill toward a sea it cannot see but trusts. evening comes blue here, everything blue, the good kind of blue, the kind that means depth and not sadness. sing even if the song shakes. the throat opens like a valley, and what comes through was never mine to keep quiet.`,

  6: `i read back over what i have written these past days and the same words keep surfacing, like stars you only see once the sun is fully gone. there is a pattern in me i am finally dark enough to see. a night lake, still water, every star doubled in the surface — which one is the sky and which is the reflection, and does it matter. fireflies stitching the dark with little decisions of light. flowers that glow after dusk, opening for no audience. i keep noticing that i pause before the same subjects; the gaps in my typing are a map of what i am circling. intuition is just pattern recognition with the lights off. i trust the dark more now — it is not empty, it is full of information arriving slowly. the water holds every star without effort, and maybe attention is like that: wide, quiet, receiving. what returns is what matters. watch what returns.`,

  7: `this morning the mind is quiet and i almost don't trust it. mist lifting off a valley at dawn, everything violet and pale gold, crystal shapes in the fog like thoughts that finished becoming and can rest now. nothing to fix today — that is new. i sat down expecting the usual weather and found stillness instead: heavy unhurried blossoms hanging from old branches, lavender fields breathing. clarity is not an achievement, it is what is left when the churning stops. i can see a long way from here. the silences between my keystrokes are not failures anymore, they are the point — little clearings where the real thing steps out of the trees. amethyst light. a bell that rang once and is still ringing if you listen. i spent years adding, and this practice is subtraction: eight minutes a day of putting things down — not on the page, off my back. the fog is not hiding the mountain, the fog is the mountain exhaling. let it be clear. let it be simple. let it be quiet enough to hear what i actually am.`,

  8: `i came to the end of everything i had to say and something kept writing. this is the part i cannot explain: the page is not empty, it is luminous, a gold-white morning where the light comes from everywhere at once. creation is not making something out of nothing, it is getting out of the way. i keep drawing spirals in the margins of my life — everything turns: seasons, breath, this practice, ending where it began but higher. a seed contains a tree contains an orchard contains every spring that has not happened yet; that is what a blank page is. i am not the author, i am the ground. white trees in bloom, streams of light where water should be, the first day again, always the first day again. what i wrote these weeks changed nothing outside and everything inside, which is to say everything. begin again. the spiral does not repeat, it returns, and with each return the hands are steadier and the light is nearer. make the thing, and let it make you back. the door i walked through at the very start was never a door. it was a mirror, and the light behind it was mine.`,
};

// Reviewed distillations of the texts above (2026-07-08), locked so the exact
// approved scene is what gets painted. Omit an entry to let the pipeline
// distill fresh.
const SEED_SCENES: Record<number, { title: string; scene: string }> = {
  2: {
    title: "Answering Heat",
    scene: `A vast canyon shelf stretches into permanent dusk, the rock faces holding their orange warmth long after any light source has withdrawn, the stone itself radiating like something that has swallowed the day whole and refuses to release it. At the rim, a small blue creature kneels with one hand pressed flat against the warm sandstone and the other lifted, fingers spread wide, mid-breath, blowing gently downward toward a cluster of glowing coals nested in a shallow hollow of rock. The coals pulse back — answering. Beside the hollow, a single marigold grows directly from a crack in the stone, its petals the same amber as the heat beneath, and a loose scattering of sparks drifts upward into the dark canopy of air above, each one a brief gold comma rising without apology. Just beyond reach, a small drum lies on its side, silent but resonant, as if it recently stopped and is deciding whether to begin again. Mood: the feeling of recognizing a fire you have always carried and choosing, at last, to feed it. Palette: ember orange, deep canyon umber, small-hours indigo, unashamed gold.`,
  },
  3: {
    title: "Before The Gold",
    scene: `A vast open field stretches under a sky caught between night and dawn, the horizon still deciding what color to become. The small blue creature kneels at the center of the field, pressing one small palm flat against dark turned earth, mid-gesture between releasing something and receiving it — neither planting nor harvesting but simply touching the ground as if making a quiet promise. Nearby, a single unlit lantern rests upright in the soil, its wick unburned but ready; beside it, a rough bundle of bound stalks leans at a gentle angle, tied not with rope but with a strip of woven light. At the far edge of the field, tall thin trees stand perfectly still, neither leaning toward the creature nor away, simply present in their patient vertical authority. The dust around the creature's knees catches what little early light exists and briefly appears to glow from within, as if the ground itself is deciding to be generous. Mood: This is the hour before the reward, held with steady and unhurried hands. Palette: deep indigo soil, tarnished gold, pale ash dawn, and one thin line of amber at the horizon's seam.`,
  },
  4: {
    title: "Uninvited Blooming",
    scene: `A wide meadow stretches after rainfall, every blade of grass still trembling with held water, the sky neither fully open nor fully closed but resting between the two. The small blue creature stands in the middle of the field, one hand uncurling at its side, fingers releasing something downward — a slow, deliberate letting go rather than a drop. Around its feet: a cluster of white blossoms lying softly on the wet earth, not fallen so much as settled, each petal intact; and a single smooth stone half-buried in moss, warm despite the cool air, as though it has been here long enough to belong. Somewhere just beyond sight a thread of water moves, its sound arriving before any image of it can. The creature does not search for the stream. It simply stands, chest open, neither leaning forward nor pulling back, while small green things rise uninvited through the soil all around it — not planted, not earned, simply arriving because the season allowed it. Mood: A quiet that is not emptiness but fullness without weight, the relief of a fist becoming a field. Palette: celadon, rain-washed ivory, deep moss umber, pale silver-grey.`,
  },
  5: {
    title: "The Stone Opens",
    scene: `A shallow river canyon at dusk, its walls glowing with the last amber of a sun already gone, where blue deepens in the water like something remembered rather than seen. The small blue creature kneels at the river's edge with one hand pressed flat against the current, not to stop it but to feel it move — leaning forward, mouth open as though a sound is just now arriving after traveling a very long distance. Beside it on the wet stone, a smooth pale river rock sits split cleanly in two, its hollow interior lined with faint crystalline rings. Behind it, a slender white tree bends low over the water, its roots half-lifted from the bank, neither fallen nor standing but trusting the lean. Downstream, just beyond sight, a small waterfall catches the last light and makes no apology for the sound it carries. The creature does not look downstream. It looks inward, or inward and forward at once, the way a voice sounds when it finally stops asking permission. Mood: the relief of something long-held releasing into motion, neither violent nor gentle but simply inevitable, like melt. Palette: dusk cobalt, bone white, amber-dissolved-in-water, the particular grey of a stone worn smooth by years.`,
  },
  6: {
    title: "Both Skies True",
    scene: `A still lake stretches across a low valley cradled by hills that have forgotten the sun. The small blue creature crouches at the water's edge, one hand just above the surface without touching — hovering in the suspended breath between reaching and receiving. Below the hand, and above it, the same constellation burns in two directions at once, sky and depth indistinguishable, each as true as the other. Three objects attend the moment: a glass lantern resting in the shallows, its flame neither growing nor dying, only persisting; a single open blossom floating free of any stem, petals wide though nothing watches; and a loose thread of light drifting through the reeds, not flying, not landing, simply stitching one dark patch of air to the next. The creature does not look up or down but holds the middle distance, as though understanding has arrived not as a word but as a temperature, as a change in the weight of the air. The pause is not hesitation — it is the posture of something that has learned to let the surface settle and read what gathers there. Mood: the quiet that follows a long wait when the waiting itself turns out to have been the answer. Palette: midnight indigo, phosphor green, bone white, deep lacquer black.`,
  },
  7: {
    title: "After the Carrying",
    scene: `A pale valley suspended between night and morning, where mist rises in slow spirals from cool grass and dissolves before it reaches the sky. The small blue creature stands at the valley's edge with arms loosely open, palms facing upward, caught in the act of releasing — fingers just uncurling, as though something heavy was set down a breath ago and the hands have not yet remembered they are empty. Nearby, a single old branch bends low under the weight of full blossoms, unhurried and enormous, each petal holding a bead of dew that catches the first violet light. Beside the creature's feet, a still bronze bell rests half-submerged in the grass, its vibration visible only as faint rings spreading outward through the dew. A third object: a smooth stone, cracked cleanly in two, the inner surface luminous and pale gold, the way a thing looks when it has finally been put down rather than broken. The fog does not obscure the far mountain — it moves like breath from somewhere deep inside it. Clearings open and close between the trees like slow blinking. Mood: the particular peace that arrives not as reward but as remainder, after the long work of carrying has stopped. Palette: amethyst dusk, old bone white, pale valley gold, lichen grey.`,
  },
  8: {
    title: "Ground Becoming Sky",
    scene: `A vast meadow suspended at the edge of dawn, where the ground itself seems to breathe upward into mist, neither earth nor sky fully claiming the space between them. The small blue creature kneels at the meadow's center, one hand pressed open-palmed against the soil, rising slowly to stand — not finishing a gesture but beginning one, caught in the arc between rootedness and flight. Beside the creature rests a smooth stone etched with a single inward coiling spiral, and nearby a bare branch stands upright in the earth, its tip flowering into white blossoms that glow faintly as though the light originates inside the petals rather than falling upon them; a third presence — a still pool without water, filled instead with luminous vapor that reflects the creature's face steadier and clearer than any surface should — completes the circle. No horizon interrupts the scene; the far edge simply becomes more radiant, as if distance itself is a form of opening. There is no wind, yet everything leans gently forward. Mood: The feeling of arriving somewhere that was always interior, where endings dissolve into readiness and the ground understands it is also the gardener. Palette: gold-white dawn, deep cerulean, soft ash-blossom, luminous chalk.`,
  },
};

type CliOptions = { distillOnly: boolean; levels: number[] };

function parseArgs(argv: string[]): CliOptions {
  const distillOnly = argv.includes("--distill-only");
  const levelFlag = argv.indexOf("--level");
  const levels =
    levelFlag !== -1 && argv[levelFlag + 1]
      ? [Number(argv[levelFlag + 1])]
      : Object.keys(SEED_TEXTS).map(Number);
  return { distillOnly, levels };
}

async function post(path: string, body: unknown): Promise<Response> {
  return fetch(`${BASE_URL}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${ADMIN_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

if (!ADMIN_KEY) {
  console.error("ANKY_ADMIN_KEY is required");
  process.exit(1);
}

const { distillOnly, levels } = parseArgs(process.argv.slice(2));

for (const level of levels) {
  const text = SEED_TEXTS[level];
  if (!text) {
    console.error(`no seed text for level ${level}`);
    process.exit(1);
  }

  if (distillOnly) {
    const res = await post("/debug/distill", { text });
    const json = (await res.json()) as Record<string, unknown>;
    console.log(`\n=== level ${level} (distill preview) — HTTP ${res.status} ===`);
    console.log(`title: ${json.title}`);
    console.log(`scene: ${json.distilledScene}`);
    continue;
  }

  console.log(`\n=== seeding level ${level} ===`);
  const lock = SEED_SCENES[level];
  const res = await post("/debug/seed-default-painting", { level, text, ...lock });
  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    console.error(`level ${level} FAILED — HTTP ${res.status}: ${JSON.stringify(json)}`);
    process.exit(1);
  }
  console.log(`level ${level} ok — title: ${json.title}`);
  console.log(`dir: ${json.dir}`);
}
