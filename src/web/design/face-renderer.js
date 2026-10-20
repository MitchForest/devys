// The Face, ported from DevysCharacter (FacePose, EyeFamily, Temperament) and
// DevysDesignSystem/DevysAvatar.swift so employees blink, wander and react exactly
// like the native apps. Mount with <canvas class="face" data-palette data-shape
// data-seed data-mood data-size>; change data-mood to blink-morph.
//
// The web app owns this file. The marketing site serves a copy: run `bun run site:sync`
// after editing; tests/site.test.ts fails while the copy differs.

const FAMILY_OF_SHAPE = {
  circle: "round",
  roundedSquare: "squircle",
  capsule: "capsule",
  blob: "wide",
  triangle: "keen",
  hexagon: "ring",
  cloud: "dot",
  drop: "tall",
};

const GEOMETRY = {
  capsule: { width: 0.16, height: 0.42, corner: 1, separation: 0.36, tilt: 0 },
  round: { width: 0.26, height: 0.26, corner: 1, separation: 0.42, tilt: 0 },
  squircle: { width: 0.26, height: 0.3, corner: 0.42, separation: 0.42, tilt: 0 },
  wide: { width: 0.3, height: 0.17, corner: 1, separation: 0.44, tilt: 0 },
  tall: { width: 0.12, height: 0.48, corner: 1, separation: 0.3, tilt: 0 },
  keen: { width: 0.24, height: 0.26, corner: 0.5, separation: 0.42, tilt: 0.16 },
  dot: { width: 0.13, height: 0.13, corner: 1, separation: 0.36, tilt: 0 },
  ring: { width: 0.26, height: 0.26, corner: 1, separation: 0.44, tilt: 0, ring: true },
};

// eyeInk on light tiles, eyeGlow on dark tiles.
const PALETTE = {
  brown: [
    [0.54, 0.4, 0.27],
    [0.85, 0.66, 0.48],
  ],
  red: [
    [0.85, 0.31, 0.34],
    [1, 0.55, 0.55],
  ],
  orange: [
    [0.88, 0.42, 0.18],
    [1, 0.62, 0.42],
  ],
  amber: [
    [0.85, 0.6, 0.15],
    [1, 0.76, 0.3],
  ],
  green: [
    [0.25, 0.6, 0.31],
    [0.49, 0.91, 0.49],
  ],
  teal: [
    [0.18, 0.62, 0.55],
    [0.3, 0.88, 0.75],
  ],
  blue: [
    [0.21, 0.47, 0.85],
    [0.55, 0.75, 1],
  ],
  purple: [
    [0.48, 0.39, 0.85],
    [0.79, 0.66, 1],
  ],
  pink: [
    [0.85, 0.29, 0.54],
    [1, 0.61, 0.85],
  ],
  gray: [
    [0.43, 0.45, 0.49],
    [0.8, 0.83, 0.86],
  ],
};

const MASK = (1n << 64n) - 1n;

class SeededGenerator {
  constructor(seed) {
    this.state = (BigInt.asUintN(64, BigInt(seed)) * 6364136223846793005n + 1n) & MASK;
  }
  next(bound) {
    this.state = (this.state * 6364136223846793005n + 1442695040888963407n) & MASK;
    return Number((this.state >> 33n) % BigInt(Math.max(bound, 1)));
  }
}

function temperament(seed) {
  const g = new SeededGenerator(seed);
  const blinkPeriod = 2.8 + g.next(34) / 10;
  return {
    blinkPeriod,
    blinkPhase: (g.next(100) / 100) * blinkPeriod,
    wanderRate: 0.16 + g.next(16) / 100,
    wanderPhase: g.next(628) / 100,
    wanderAmp: 0.35 + g.next(50) / 100,
  };
}

function blinkCloseness(t, time) {
  const cycle = (time + t.blinkPhase) % t.blinkPeriod;
  return cycle < 0.16 ? 1 - Math.abs(cycle / 0.08 - 1) : 0;
}

function expression(mood) {
  const e = { height: 1, lift: 0, asym: 0, gx: 0, gy: 0, render: null, wanders: false };
  switch (mood) {
    case "idle":
      e.wanders = true;
      break;
    case "listening":
      e.height = 1.08;
      break;
    case "thinking":
      Object.assign(e, { height: 0.72, gx: -0.5, gy: -0.75 });
      break;
    case "working":
      Object.assign(e, { height: 0.34, gy: 0.35 });
      break;
    case "waiting":
      Object.assign(e, { height: 1.06, asym: -0.16 });
      break;
    case "celebrate":
      e.render = "arc";
      break;
    case "oops":
      e.render = "cross";
      break;
    case "asleep":
      Object.assign(e, { height: 0.4, lift: 0.08 });
      break;
  }
  return e;
}

function budgetFor(size) {
  return size < 28 ? "minimal" : size < 64 ? "poses" : "full";
}

function pose(face, mood, time, pokePhase, motion) {
  if (mood === "off") return { standby: true };
  const geo = GEOMETRY[face.family];
  const temp = face.temperament;
  const motionTime = motion ? time : (face.seed % 64) * 1.37;
  const ex = expression(mood);
  let render = geo.ring ? "ring" : "fill";
  let height = ex.height;
  let width = 1;
  let gx = ex.gx;
  let gy = ex.gy;

  if (face.budget === "full" && pokePhase != null && pokePhase >= 0 && pokePhase < 0.9) {
    render = "arc";
    if (motion) {
      const spring = Math.exp(-pokePhase * 5) * Math.cos(pokePhase * 22) * 0.1;
      width = 1 + spring;
      height *= 1 - spring;
    }
  } else if (ex.render) {
    render = ex.render;
  }

  if (face.budget !== "minimal" && ex.wanders) {
    gx = Math.sin(motionTime * temp.wanderRate * 1.5 + temp.wanderPhase) * temp.wanderAmp;
    gy = Math.cos(motionTime * temp.wanderRate + temp.wanderPhase * 2) * temp.wanderAmp * 0.6;
  }
  if ((render === "fill" || render === "ring") && mood !== "asleep") {
    height *= 1 - blinkCloseness(temp, time) * 0.9;
  }

  const cx = 0.5 + gx * 0.055;
  const cy = 0.5 + gy * 0.055 + ex.lift * 0.1;
  const eyes = [-1, 1].map((dir) => {
    const w = geo.width * width;
    const h = Math.max(geo.height * height, 0.02);
    let eyeRender = render;
    if (eyeRender === "ring" && h < geo.height * 0.5) eyeRender = "fill";
    return {
      x: cx + (dir * geo.separation) / 2,
      y: cy + (dir > 0 ? ex.asym * 0.16 : 0),
      w,
      h,
      r: (Math.min(w, h) / 2) * geo.corner,
      tilt: geo.tilt * dir,
      render: eyeRender,
    };
  });
  const dots = mood === "thinking" && face.budget === "full" ? Math.floor(motionTime * 2) % 4 : 0;
  const zeds =
    mood === "asleep" && face.budget !== "minimal" ? 1 + (Math.floor(motionTime * 0.8) % 2) : 0;
  return { eyes, dots, zeds };
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, Math.max(0, Math.min(r, w / 2, h / 2)));
}

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
const faces = new Set();

function mount(canvas) {
  const size = Number(canvas.dataset.size || 32);
  const face = {
    canvas,
    ctx: canvas.getContext("2d"),
    size,
    seed: Number(canvas.dataset.seed || 1),
    family: FAMILY_OF_SHAPE[canvas.dataset.shape] || "round",
    palette: PALETTE[canvas.dataset.palette] || PALETTE.blue,
    tile: canvas.dataset.tile !== "false",
    // data-budget lets a small brand mark carry a hero face's full motion.
    budget: canvas.dataset.budget || budgetFor(size),
    mood: canvas.dataset.mood || "idle",
    previousMood: null,
    moodChangedAt: 0,
    pokedAt: null,
    lastDraw: 0,
    visible: true,
  };
  face.temperament = temperament(face.seed);
  const dpr = Math.min(devicePixelRatio || 1, 3);
  canvas.width = size * dpr;
  canvas.height = size * dpr;
  canvas.style.width = `${size}px`;
  canvas.style.height = `${size}px`;
  face.ctx.scale(dpr, dpr);
  canvas.setAttribute("role", canvas.getAttribute("aria-label") ? "img" : "presentation");
  if (face.budget === "full") {
    canvas.addEventListener("click", () => (face.pokedAt = performance.now() / 1000));
    canvas.style.cursor = "pointer";
  }
  visibility.observe(canvas);
  faces.add(face);
  draw(face, performance.now() / 1000);
  return face;
}

const visibility = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    for (const face of faces) if (face.canvas === entry.target) face.visible = entry.isIntersecting;
  }
});

function draw(face, time) {
  const { ctx, size: side, canvas } = face;
  const style = getComputedStyle(canvas);
  const dark = style.getPropertyValue("--is-dark").trim() === "1";
  const [r, g, b] = face.palette[dark ? 1 : 0];
  const eyeColor = `rgb(${r * 255}, ${g * 255}, ${b * 255})`;
  ctx.clearRect(0, 0, side, side);

  if (face.tile) {
    roundRect(ctx, 0.75, 0.75, side - 1.5, side - 1.5, side * 0.24);
    ctx.fillStyle = style.getPropertyValue("--sheet").trim() || "#fff";
    ctx.fill();
    ctx.lineWidth = Math.max(1, side * 0.012);
    ctx.strokeStyle = dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.10)";
    ctx.stroke();
    if (dark && side >= 34 && face.mood !== "off") {
      const glow = ctx.createRadialGradient(side / 2, side / 2, 1, side / 2, side / 2, side * 0.55);
      glow.addColorStop(0, `rgba(${r * 255}, ${g * 255}, ${b * 255}, 0.13)`);
      glow.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.ellipse(side / 2, side / 2, side / 2, side / 2, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // Blink-morph: the old expression closes, the new one opens.
  const motion = !reduceMotion.matches;
  let mood = face.mood;
  let morph = 1;
  const since = time - face.moodChangedAt;
  if (face.previousMood && since >= 0 && since < 0.32 && motion) {
    const phase = since / 0.32;
    if (phase < 0.5) {
      mood = face.previousMood;
      morph = 1 - phase * 2;
    } else morph = phase * 2 - 1;
  }
  const poke = face.pokedAt == null ? null : time - face.pokedAt;
  const p = pose(face, mood, time, poke, motion);

  if (p.standby) {
    const pulse = motion ? 0.22 + 0.14 * Math.sin(time * 1.6) : 0.3;
    roundRect(
      ctx,
      side / 2 - side * 0.08,
      side / 2 - side * 0.02,
      side * 0.16,
      side * 0.04,
      side * 0.02,
    );
    ctx.fillStyle = dark ? `rgba(255,255,255,${pulse})` : `rgba(0,0,0,${pulse})`;
    ctx.fill();
    return;
  }

  const inset = face.tile ? side * 0.03 : 0;
  const span = side - inset * 2;
  ctx.fillStyle = eyeColor;
  ctx.strokeStyle = eyeColor;
  for (const eye of p.eyes) {
    const w = eye.w * span;
    const h = Math.max(eye.h * span * morph, side * 0.015);
    ctx.save();
    ctx.translate(inset + eye.x * span, inset + eye.y * span);
    ctx.rotate(eye.tilt);
    if (eye.render === "fill") {
      roundRect(ctx, -w / 2, -h / 2, w, h, Math.max(eye.r * span, 1));
      ctx.fill();
    } else if (eye.render === "ring") {
      ctx.lineWidth = Math.max(w * 0.28, 2);
      ctx.beginPath();
      ctx.ellipse(0, 0, (w * 0.72) / 2, (h * 0.72) / 2, 0, 0, Math.PI * 2);
      ctx.stroke();
    } else if (eye.render === "arc") {
      const radius = Math.max(w, side * 0.16) * 0.62 * morph;
      ctx.lineWidth = Math.max(side * 0.045, 2.5);
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(0, radius * 0.45, radius, Math.PI * 1.15, Math.PI * 1.85);
      ctx.stroke();
    } else if (eye.render === "cross") {
      const length = Math.max(w, side * 0.14) * 0.9 * morph;
      const thick = Math.max(side * 0.035, 2);
      for (const angle of [Math.PI / 4, -Math.PI / 4]) {
        ctx.save();
        ctx.rotate(angle);
        roundRect(ctx, -length / 2, -thick / 2, length, thick, thick / 2);
        ctx.fill();
        ctx.restore();
      }
    }
    ctx.restore();
  }

  if (p.dots > 0 && side > 80) {
    const eye = p.eyes[1];
    ctx.globalAlpha = 0.75;
    for (let i = 0; i < p.dots; i++) {
      ctx.beginPath();
      const d = side * 0.028;
      ctx.ellipse(
        eye.x * side + side * 0.14 + i * side * 0.05 + d / 2,
        side * 0.22 + d / 2,
        d / 2,
        d / 2,
        0,
        0,
        Math.PI * 2,
      );
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
  const zeds = [
    [0.7, 0.3, 0.1, 0.85],
    [0.8, 0.18, 0.07, 0.55],
  ];
  for (let i = 0; i < p.zeds; i++) {
    const [ox, oy, scale, alpha] = zeds[i];
    const w = side * scale;
    ctx.globalAlpha = alpha;
    ctx.lineWidth = Math.max(side * 0.024, 1.4);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(side * ox, side * oy);
    ctx.lineTo(side * ox + w, side * oy);
    ctx.lineTo(side * ox, side * oy + w * 0.9);
    ctx.lineTo(side * ox + w, side * oy + w * 0.9);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }
}

const INTERVAL = { full: 1 / 30, poses: 1 / 10, minimal: 1 / 4 };

function loop(now) {
  const time = now / 1000;
  for (const face of faces) {
    const mood = face.canvas.dataset.mood || "idle";
    if (mood !== face.mood) {
      face.previousMood = face.mood;
      face.mood = mood;
      face.moodChangedAt = time;
      face.lastDraw = 0;
    }
    const transitioning =
      time - face.moodChangedAt < 0.32 || (face.pokedAt && time - face.pokedAt < 0.9);
    const interval = transitioning ? 1 / 30 : INTERVAL[face.budget];
    if (face.visible && time - face.lastDraw >= interval) {
      face.lastDraw = time;
      draw(face, time);
    }
  }
  requestAnimationFrame(loop);
}

export function mountFaces(root = document) {
  root.querySelectorAll("canvas.face").forEach((canvas) => {
    if (!canvas.dataset.mounted) {
      canvas.dataset.mounted = "1";
      mount(canvas);
    }
  });
}

/** Stops drawing a canvas that has left the page (apps remove faces as views change). */
export function unmountFace(canvas) {
  for (const face of faces) if (face.canvas === canvas) faces.delete(face);
  visibility.unobserve(canvas);
}

export function redrawFaces() {
  for (const face of faces) face.lastDraw = 0;
}

requestAnimationFrame(loop);
