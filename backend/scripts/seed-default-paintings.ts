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
  const res = await post("/debug/seed-default-painting", { level, text });
  const json = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    console.error(`level ${level} FAILED — HTTP ${res.status}: ${JSON.stringify(json)}`);
    process.exit(1);
  }
  console.log(`level ${level} ok — title: ${json.title}`);
  console.log(`dir: ${json.dir}`);
}
