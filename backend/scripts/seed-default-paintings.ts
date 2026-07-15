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
// Levels 9–15 are the second octave: the same seven energies turned outward,
// the light that was found now becoming a gift — devotion (the kept fire),
// generosity (the opened granary), shelter (the sheltering tree), transmission
// (the bell and the sea), guidance (the faithful beam), transparency (the house
// of clear glass), and passing the flame. Where the first octave ended "the
// door was a mirror," the second ends "the door was always a window." Beyond 15
// the last painting holds until the arc is extended again.
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

  9: `nine and the fire is not new anymore, it is kept. i used to chase the spark like it might not come again and now i know the secret is not the spark, it is the tending — you feed it on the mornings you don't feel it and it feeds you back on the mornings you do. i think about a smith at a forge, the patient violence of it, iron going orange then white, hammered not because the metal is wrong but because it is becoming. coals banked under grey ash that look dead and are not, that answer the smallest breath. i have stopped waiting to feel ready. readiness is a fire you keep, not a weather you wait for. bronze light, the deep red of heat with somewhere still to go, a single anvil worn smooth by ten thousand returns. what i am making at this forge is not on the page, it is the hands themselves, the arm that knows the weight now, the discipline that used to feel like a cage and turns out to have been a hearth. keep the fire. it was never about the flame that leaps, it was about the coals that stay.`,

  10: `ten and the field is heavy and i finally understand it was never mine to hoard. i spent so long counting the grain, afraid there would not be enough, and the whole time the point of a harvest is that you open the doors and let people in. i keep seeing a granary at the edge of a gold field, its big doors thrown wide, light and wheat spilling out onto the ground, more than one body could ever eat. what you keep rots and what you give multiplies, that is the oldest and least believed math. warm amber everywhere, the color of bread and late sun and honey held up to a window. i give away the sentences now, i give away the mornings, i give away the small steadiness i built and it does not diminish me, it is the opposite. a long wooden table set outside under the trees. baskets passed hand to hand. the wealth was never the pile, it was the passing. take some. there is so much. it grew while i was not looking, the way abundance always does, quietly, in the tending, and now the doors are open and they are staying open.`,

  11: `eleven and my heart has grown a roof over it, or under it, a place where others can come out of the rain. it is not enough anymore to have healed, the healing wants to be useful. i think of a great old tree standing alone in a wet meadow, its branches so wide and low that a whole flock could shelter there, and it asks nothing, it just stands and holds the rain off. green everywhere, the deep green of moss and long grass, and rose where the blossoms open along the sheltering branches. i used to protect my softness like it was a wound and now i know it is a shelter — the softest thing in the field is the thing everything else comes to. petals and rain on wide leaves. small creatures gathered under the canopy, unafraid. tenderness turned outward is just called care. i hold the door of my chest open the way that tree holds its branches, without effort, without keeping score, because a heart that has been mended knows exactly what the rain feels like and will not send anyone back out into it.`,

  12: `twelve and the river finally reached the sea. all those years finding the voice, saying the true thing in the small room, and now the true thing wants to travel, wants to be heard past the walls of me. i think of a bell in a tower at dusk, one clear note going out over the whole valley, reaching the far farms, reaching people i will never meet, asking nothing of them except that they hear. deep cobalt water opening into something vast, bronze light on the swells. the voice is not for me anymore, it was never only for me — a song kept in the throat is just a stone, a song given away is weather, it changes the temperature of a whole town. i speak and it carries now, downstream, out past the mouth of the river into the blue that has no other side. bronze bell, blue distance, white birds lifting off the water at the sound. say the true thing loud enough that it reaches the next person still standing at the edge of their own ice, and let them know the water moves, it always finds a way, it found a way in me and it will find a way in them.`,

  13: `thirteen and the seeing turned into a light for other people to steer by. i learned to read the dark, to trust what returns in the quiet, and now that seeing wants to stand somewhere high and burn so the ones out on the water can find the rocks and the harbor. a lighthouse on a black headland, one long beam sweeping the night sea, patient, turning, not anxious, just faithful — the same arc again and again, which is the whole job. indigo dark, the gold of the beam cutting it, foam catching the light where the waves break far below. intuition was never only for my own navigation; the pattern i can see with the lights off is a map i can hold up for someone lost. stars doubled on black water, a single warm window high in the tower. i stand at the top of the long stair and keep the lamp trimmed and lit, and i do not need to know which ship, or whether they wave — the beam goes out, the beam returns, and somewhere in the dark a frightened someone corrects their course and does not know my name, and that is exactly as it should be.`,

  14: `fourteen and there is nothing left to hide, which is a stranger relief than i expected. clarity used to mean i could see, and now it means i can be seen — the fog lifted off the valley and lifted off me too, and the light goes straight through. i think of a house made all of clear glass standing in a still dawn, no dark rooms, no locked doors, the same amethyst morning inside as out, everything simply visible and unashamed. i spent years building walls to keep the real thing safe and it turns out the real thing was only ever endangered by the walls. pale violet light, crystal and water-clear air, long soft shadows of nothing in particular. to be transparent is not to be exposed, it is to be at peace enough that there is no gap between the inside and the outside. a glass house holds the light instead of blocking it. i can see a long way from here and a long way into here, and it is the same distance now, and it is quiet, and it is clear, and there is a person standing in the open door who turns out to be me, with nothing in my hands, hiding nothing, home.`,

  15: `fifteen and i understand at last that the light was never meant to stay mine. the first door was a mirror and the light behind it was mine — and this door, this one, is a window i throw open so the light goes out. creation stops being about making a thing and becomes about becoming a source: you fill until you overflow, and the overflow is the whole point, the overflow is the gift. i see a figure on a hilltop at dawn holding a lit flame out toward a long line of unlit lamps stretching down into the valley, and the flame does not shrink when it is shared, it multiplies, it always multiplies, one becomes two becomes a valley full of small warm lights. gold-white morning, the first day again but wider, the spiral come round to a height where it can finally give. white trees, streams of light, a hand reaching toward another hand. i am not the author and i am not even only the ground anymore, i am the passing-on, the place where the light does not stop. take the flame. it was given to me and i am giving it to you. begin again — but this time begin someone else. the practice was never only mine. the door was always a window. the light was always meant to travel, and now it does, and now it is yours.`,
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
    scene: `A still lake stretches across a low valley cradled by hills that have forgotten the sun. The small blue creature crouches at the water's edge, one hand just above the surface without touching — hovering in the suspended breath between reaching and receiving. Below the hand, and above it, the same constellation burns in two directions at once, sky and depth indistinguishable, each as true as the other. Three objects attend the moment: a glass lantern resting in the shallows, its small amber flame steady and generous, pooling warm gold across the still water around it and up the nearest reeds; a single open blossom floating free of any stem, petals wide though nothing watches; and a loose thread of light drifting through the reeds, not flying, not landing, simply stitching one dark patch of air to the next. The creature does not look up or down but holds the middle distance, as though understanding has arrived not as a word but as a temperature, as a change in the weight of the air. The pause is not hesitation — it is the posture of something that has learned to let the surface settle and read what gathers there. Mood: the quiet that follows a long wait when the waiting itself turns out to have been the answer. Palette: midnight indigo, phosphor green, bone white, warm lantern amber.`,
  },
  7: {
    title: "After the Carrying",
    scene: `A pale valley suspended between night and morning, where mist rises in slow spirals from cool grass and dissolves before it reaches the sky. The small blue creature stands at the valley's edge with arms loosely open, palms facing upward, caught in the act of releasing — fingers just uncurling, as though something heavy was set down a breath ago and the hands have not yet remembered they are empty. Nearby, a single old branch bends low under the weight of full blossoms, unhurried and enormous, each petal holding a bead of dew that catches the first violet light. Beside the creature's feet, a still bronze bell rests half-submerged in the grass, its vibration visible only as faint rings spreading outward through the dew. A third object: a smooth stone, cracked cleanly in two, the inner surface luminous and pale gold, the way a thing looks when it has finally been put down rather than broken. The fog does not obscure the far mountain — it moves like breath from somewhere deep inside it. Clearings open and close between the trees like slow blinking. Mood: the particular peace that arrives not as reward but as remainder, after the long work of carrying has stopped. Palette: amethyst dusk, old bone white, pale valley gold, lichen grey.`,
  },
  8: {
    title: "Ground Becoming Sky",
    scene: `A vast meadow suspended at the edge of dawn, where the ground itself seems to breathe upward into mist, neither earth nor sky fully claiming the space between them. The small blue creature kneels at the meadow's center, one hand pressed open-palmed against the soil, rising slowly to stand — not finishing a gesture but beginning one, caught in the arc between rootedness and flight. Beside the creature rests a smooth stone etched with a single inward coiling spiral, and nearby a bare branch stands upright in the earth, its tip flowering into white blossoms that glow faintly as though the light originates inside the petals rather than falling upon them; a third presence — a still pool without water, filled instead with luminous vapor that reflects the creature's face steadier and clearer than any surface should — completes the circle. No horizon interrupts the scene; the far edge simply becomes more radiant, as if distance itself is a form of opening. There is no wind, yet everything leans gently forward. Mood: The feeling of arriving somewhere that was always interior, where endings dissolve into readiness and the ground understands it is also the gardener. Palette: gold-white dawn, deep cerulean, soft ash-blossom, luminous chalk.`,
  },
  9: {
    title: "The Kept Fire",
    scene: `A low stone forge stands in permanent pre-dawn under a vast banked sky, its hearth glowing a deep steady red-orange that throws warm light across the worn ground without any flame leaping — heat that has learned to stay. The small blue creature stands at the anvil, one hand resting flat and unhurried on the warm iron, the other lifted mid-motion holding a single ember on an open palm as though weighing rather than gripping it, neither igniting nor extinguishing, simply keeping. Three attend the moment: a bed of grey-ashed coals in the forge mouth that pulse brighter where the creature's breath reaches them, alive under their pale skin of ash; a smith's hammer laid down at rest across the anvil, its head worn mirror-smooth by ten thousand patient returns; and a single iron nail standing upright in a crack of the stone, glowing faintly from within, half-made and unashamed of it. No fire leaps anywhere in the scene, yet everything is warm. Mood: the quiet authority of a fire that is kept rather than chased — devotion as a hearth, not a spark. Palette: banked ember red, worn iron grey, deep bronze, small-hours indigo, one seam of white heat.`,
  },
  10: {
    title: "The Opened Granary",
    scene: `A tall wooden granary stands at the edge of a heavy gold field under a warm late-afternoon sky, its great double doors thrown fully open, wheat and light spilling together over the threshold onto the ground in a bright unhoarded heap. The small blue creature stands at the doors with both arms mid-gesture, one hand releasing a fistful of grain that catches the sun as it falls, the other open and empty and unworried by its emptiness. Three objects hold the scene: a long plain wooden table set outside under the field's edge trees, bare but waiting, generous by intention; a woven basket tipped on its side with more grain pouring out than any container could keep; and a single loaf of pale bread resting on the threshold stone, still warm, uncut, meant to be broken by other hands. The field beyond stretches gold to the horizon, more than one harvest could ever hold. Mood: the particular abundance that arrives only when the doors are opened — wealth as passing, not pile. Palette: wheat gold, honey amber, warm bread ivory, late-sun ochre, soft green field-edge.`,
  },
  11: {
    title: "The Sheltering Tree",
    scene: `A great old tree stands alone in a wide rain-wet meadow under a soft grey-green sky, its branches spread so low and so far they form a living roof, the ground beneath it dry and warm while rain falls gently everywhere beyond the canopy's edge. The small blue creature stands beneath the tree with one hand raised to rest against the underside of a low branch and the other held open at its side, palm out, offering the shelter rather than taking it. Three presences complete the moment: a scatter of small creatures gathered close around the creature's feet, unafraid, out of the rain; pale rose blossoms opening along the sheltering branches, luminous against the wet dark bark; and a single wide green leaf cupped on the ground, holding a small pool of caught rainwater like an offered drink. The tree asks for nothing and simply holds. Mood: tenderness turned outward — a healed heart become a shelter, care without keeping score. Palette: deep moss green, rain-silver, soft rose, wet-bark umber, pale meadow gold.`,
  },
  12: {
    title: "The Bell and the Sea",
    scene: `A weathered bronze bell hangs in an open stone tower at the mouth of a river, where the water finally widens into a vast dusk-blue sea that opens without any far shore. The small blue creature stands at the bell with one hand pressed flat against its warm curved metal, feeling rather than striking it, the other lifted toward the opening distance as a single clear note visibly leaves the bell in soft concentric rings of light travelling out over the swells. Three things attend: the river behind narrowing to its mouth, its current still moving with old patience; white birds lifting off the water all at once at the sound, scattering upward into the blue; and a small round stone resting on the tower ledge, split cleanly open, its hollow lined with faint pale rings like a bell that has already answered. The sound reaches farms and figures too far to see. Mood: the voice that has stopped being only for the small room — a true thing given away, carrying past the walls. Palette: dusk cobalt, deep sea blue, weathered bronze, foam white, pale amber tower-stone.`,
  },
  13: {
    title: "The Faithful Beam",
    scene: `A tall pale lighthouse stands on a black headland above a night sea, its single warm beam sweeping the dark in a long patient arc, gold light cutting the indigo and catching the white foam where waves break far below. The small blue creature stands at the lamp room's open rail, one hand on the brass housing of the light, the other lifted to shield its eyes as it watches the beam travel out — not anxious, simply faithful, the same arc given again and again. Three objects hold the scene: the great lamp itself, steady and unblinking, pouring its gold outward rather than inward; a small trimmed hand-lantern hung by the door, kept ready; and a folded chart weighted open on the sill, its coastline marked, a map made to be held up for someone else. Stars double themselves on the black water below, and somewhere out in the dark a small unseen boat corrects its course. Mood: the seeing that became a light for others to steer by — vision as service, the beam that goes out and returns. Palette: deep indigo night, faithful beam gold, foam white, black headland stone, one warm window.`,
  },
  14: {
    title: "The House of Clear Glass",
    scene: `A house made entirely of clear glass stands alone in a still amethyst dawn meadow, no dark rooms and no closed doors, the pale violet morning passing straight through it so the inside and outside are the same luminous air. The small blue creature stands in the open glass doorway with both hands loose and empty at its sides, hiding nothing, its own faint reflection and the far meadow visible through it at once. Three presences complete the scene: a single tall pane catching the low sun and throwing a long soft rectangle of light across the dewed grass; a smooth crystal resting on the glass sill, water-clear, refracting a small quiet rainbow onto the floor; and a plain open bowl on a glass table holding nothing but light. No wall casts a hard shadow; everything is soft-edged and seen. Mood: the peace of having nothing left to hide — clarity become transparency, at home in the open. Palette: pale amethyst dawn, water-clear crystal, soft rose-gold light, luminous chalk white, faint meadow green.`,
  },
  15: {
    title: "The Passed Flame",
    scene: `A high grassy hilltop at the very first light of dawn, where a gold-white morning breaks wider than any horizon should allow. The small blue creature stands at the hill's crest holding a single lit flame cupped in both hands and extending it outward and downward toward the first of a long line of unlit lamps that descends into the misty valley below, waiting. Three things hold the scene: the near lamp just catching, its new small light blooming to life; the long descending line of dark lamps stretching down into the valley, each one a quiet promise; and a bare white tree beside the creature breaking into blossom that glows as though lit from within, streams of pale light running where its roots should be. The given flame has not shrunk — it burns brighter for being passed. No far edge closes the scene; the distance simply grows more radiant, a spiral come round to a height that can finally give. Mood: the light understood at last as something meant to travel — creation become source, the door become a window. Palette: gold-white dawn, warm flame amber, soft valley mist-violet, luminous blossom white, deep cerulean sky.`,
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

  // Already-packaged levels are skipped so an interrupted run resumes where
  // it stopped; pass --force to re-paint (replace) a level on purpose.
  if (!process.argv.includes("--force")) {
    const check = await fetch(`${BASE_URL}/debug/seed-default-painting?level=${level}`, {
      headers: { Authorization: `Bearer ${ADMIN_KEY}` },
    });
    const state = (await check.json()) as { packaged?: boolean; title?: string | null };
    if (state.packaged) {
      console.log(`\n=== level ${level} already packaged ("${state.title}") — skipping ===`);
      continue;
    }
  }

  console.log(`\n=== seeding level ${level} ===`);
  const lock = SEED_SCENES[level];
  const res = await post("/debug/seed-default-painting", { level, text, ...lock });
  const json = (await res.json()) as Record<string, unknown>;
  if (res.status !== 202) {
    console.error(`level ${level} FAILED to start — HTTP ${res.status}: ${JSON.stringify(json)}`);
    process.exit(1);
  }

  // The run is detached server-side; poll until it lands (or dies).
  const deadline = Date.now() + 20 * 60 * 1000;
  let settled = false;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 15_000));
    const statusRes = await fetch(`${BASE_URL}/debug/seed-default-painting?level=${level}`, {
      headers: { Authorization: `Bearer ${ADMIN_KEY}` },
    });
    const status = (await statusRes.json()) as {
      running?: boolean;
      result?: { ok: boolean; title?: string; error?: string } | null;
      packaged?: boolean;
      title?: string | null;
    };
    if (status.running) {
      console.log(`level ${level} … still painting`);
      continue;
    }
    if (status.result?.ok || status.packaged) {
      console.log(`level ${level} ok — title: ${status.result?.title ?? status.title}`);
      settled = true;
    } else {
      console.error(`level ${level} FAILED — ${status.result?.error ?? "no package, no error"}`);
      process.exit(1);
    }
    break;
  }
  if (!settled) {
    console.error(`level ${level} timed out after 20 minutes of polling`);
    process.exit(1);
  }
}
