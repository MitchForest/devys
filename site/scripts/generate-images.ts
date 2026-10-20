// Generates the site's photography with Higgsfield SOUL Cinema.
// Run from site/: `bun scripts/generate-images.ts [name...]`. Bun loads .env.local.
// Outputs are downloaded into assets/images because Higgsfield retains them for ~7 days.
// Idempotency keys include the seed: change the seed to request a new take.

const key = process.env.HIGGSFIELD_API_KEY;
if (!key) throw new Error("HIGGSFIELD_API_KEY is missing; copy .env.example to .env.local.");

const endpoint = "https://api.higgsfield.ai/higgsfield-ai/soul/cinema";
const headers = { Authorization: `Key ${key}`, "Content-Type": "application/json" };

const shots: Record<string, { prompt: string; aspect_ratio: string; seed: number }> = {
  hero: {
    prompt:
      "Wide cinematic photograph of a quiet teak deck at a Thai island beach villa at golden hour, a linen hammock and a low wooden table with a closed laptop and an iPhone, turquoise Andaman sea and limestone karsts in soft haze, warm peach and rose evening light, calm, minimal, lots of negative space in the sky, no people, editorial travel photography, 35mm film grain",
    aspect_ratio: "16:9",
    seed: 4127,
  },
  boat: {
    prompt:
      "Aerial top-down photograph of a single wooden longtail boat resting on clear turquoise water over white sand in Thailand, gentle ripples, soft morning light, serene and minimal, vast empty water, editorial travel photography, subtle film grain",
    aspect_ratio: "16:9",
    seed: 8812,
  },
  desk: {
    prompt:
      "Cinematic photograph of a cluttered home office desk late at night, three glowing monitors full of notifications and spreadsheets, sticky notes, cold coffee, tangled cables, harsh blue screen light, moody and claustrophobic, no people, shallow depth of field, film grain",
    aspect_ratio: "16:9",
    seed: 2291,
  },
  morning: {
    prompt:
      "Cinematic photograph of a person seen from behind sitting on a wooden pier over calm turquoise water in Thailand at sunrise, holding a coffee cup, an iPhone face down beside them, soft pastel peach and lavender sky, tranquil, minimal composition with the horizon low, editorial, film grain",
    aspect_ratio: "3:4",
    seed: 5530,
  },
};

type Status = { status: string; images?: { url: string }[]; error?: string };

async function generate(name: string) {
  const shot = shots[name];
  if (!shot) throw new Error(`Unknown shot ${name}`);
  const submit = await fetch(endpoint, {
    method: "POST",
    headers: { ...headers, "Idempotency-Key": `devys-site-${name}-${shot.seed}` },
    body: JSON.stringify({ ...shot, resolution: "1080p", enhance_prompt: false, batch_size: 1 }),
  });
  if (!submit.ok) throw new Error(`${name}: submit ${submit.status} ${await submit.text()}`);
  const { status_url } = (await submit.json()) as { status_url: string };

  for (let delay = 3000; ; delay = Math.min(delay * 1.5, 15000)) {
    await Bun.sleep(delay);
    // A transient non-JSON status response is retried on the next poll.
    const result = (await (
      await fetch(status_url, { headers })
    )
      .json()
      .catch(() => ({ status: "unknown" }))) as Status;
    if (result.status === "completed" && result.images?.[0]) {
      const source = `assets/images/${name}.source.png`;
      await Bun.write(source, await (await fetch(result.images[0].url)).arrayBuffer());
      // Ship a compressed JPEG; sips ships with macOS.
      await Bun.$`sips -s format jpeg -s formatOptions 80 -Z 2400 ${source} --out assets/images/${name}.jpg`.quiet();
      await Bun.$`rm ${source}`;
      console.log(`${name}: saved assets/images/${name}.jpg`);
      return;
    }
    if (["failed", "nsfw", "canceled"].includes(result.status)) {
      throw new Error(`${name}: ${result.status} ${result.error ?? ""}`);
    }
  }
}

const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(shots);
const results = await Promise.allSettled(names.map(generate));
for (const result of results) if (result.status === "rejected") console.error(result.reason);
