// ASCII shader backgrounds. Each cell's value comes from a small field function
// and maps to a glyph by density; color changes only between bands so draws stay cheap.
//   journey: owner-operated chaos (turbulence plus flashing chores) easing into
//            calm water as `calm` goes 0 → 1.
//   waves:   quiet aurora water behind the manifesto.
//   horizon: a sea at night; an aurora sun rises out of it as `progress` goes 0 → 1.
// Every field drifts with `offset` (scroll parallax, in px) and ripples under the pointer.

const RAMP = " .:-=+*#%@";
const SUN = " .:*%@";
const CHORES = [
  "@you",
  "URGENT",
  "Re: Re: Re:",
  "invoice overdue",
  "standup?",
  "deploy failed",
  "3 unread",
  "quick call?",
  "ping",
  "who owns this",
  "chargeback",
  "can you look",
  "fwd: fwd:",
  "EOD",
  "reminder",
  "approve spend",
];

function hash(x, y, z) {
  let h = (x * 374761393 + y * 668265263 + z * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}

function smooth(t) {
  return t * t * (3 - 2 * t);
}

function noise(x, y, z) {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const zi = Math.floor(z);
  const xf = smooth(x - xi);
  const yf = smooth(y - yi);
  const zf = smooth(z - zi);
  const lerp = (a, b, t) => a + (b - a) * t;
  const plane = (zz) =>
    lerp(
      lerp(hash(xi, yi, zz), hash(xi + 1, yi, zz), xf),
      lerp(hash(xi, yi + 1, zz), hash(xi + 1, yi + 1, zz), xf),
      yf,
    );
  return lerp(plane(zi), plane(zi + 1), zf);
}

// Ocean value at a cell; `depth` is 0 at the far horizon and 1 at the viewer.
function water(x, y, depth, t) {
  const persp = 0.35 + depth * 1.6;
  const v =
    Math.sin((x * 0.09) / persp + t * 0.7 + Math.sin(depth * 6 + t * 0.35) * 1.6) * 0.45 +
    Math.sin((x * 0.034) / persp - t * 0.45 + y * 0.35) * 0.35 +
    (noise(x * 0.06, y * 0.12, t * 0.18) - 0.5) * 0.7;
  return (v + 1.1) / 2.2;
}

function chaos(x, y, t) {
  const n = noise(x * 0.13, y * 0.24, t * 1.6) * 0.65 + noise(x * 0.5, y * 0.9, t * 4) * 0.35;
  return Math.pow(n, 1.6) * 1.15;
}

export class AsciiField {
  constructor(canvas, { mode = "waves", cell = 13, calm = 1, palette } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.mode = mode;
    this.cell = cell;
    this.calm = calm;
    this.progress = 0;
    this.offset = 0;
    this.palette = palette;
    this.words = [];
    this.pointer = null;
    this.visible = false;
    this.reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.start = performance.now();
    this.last = 0;
    new ResizeObserver(() => this.resize()).observe(canvas);
    new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
      if (this.visible) this.tick(performance.now());
    }).observe(canvas);
    const host = canvas.closest("section") ?? canvas.parentElement;
    host.addEventListener("pointermove", (event) => {
      const rect = canvas.getBoundingClientRect();
      this.pointer = { x: event.clientX - rect.left, y: event.clientY - rect.top };
    });
    host.addEventListener(
      "pointerleave",
      () => this.pointer && (this.pointer.left = performance.now()),
    );
    this.resize();
  }

  resize() {
    const dpr = Math.min(devicePixelRatio || 1, 2);
    const { width, height } = this.canvas.getBoundingClientRect();
    this.width = width;
    this.height = height;
    this.canvas.width = Math.max(1, width * dpr);
    this.canvas.height = Math.max(1, height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.cw = this.cell * 0.62;
    this.ch = this.cell * 1.18;
    this.cols = Math.ceil(width / this.cw);
    this.rows = Math.ceil(height / this.ch);
    this.render(this.time());
  }

  time() {
    return this.reduce ? 12 : (performance.now() - this.start) / 1000;
  }

  tick(now) {
    if (!this.visible || this.reduce) return;
    if (now - this.last > 1000 / 30) {
      this.last = now;
      this.render((now - this.start) / 1000);
    }
    requestAnimationFrame((n) => this.tick(n));
  }

  // A ring that spreads from the pointer and fades once it leaves.
  ripple(x, y, t) {
    const p = this.pointer;
    if (!p || this.reduce) return 0;
    const fade = p.left ? Math.max(0, 1 - (performance.now() - p.left) / 900) : 1;
    if (fade <= 0) return 0;
    const dx = (x * this.cw - p.x) / this.cw;
    const dy = (y * this.ch - p.y) / this.ch;
    const d = Math.sqrt(dx * dx * 0.35 + dy * dy);
    if (d > 26) return 0;
    return Math.sin(d * 0.9 - t * 7) * Math.exp(-d * 0.11) * 0.55 * fade;
  }

  begin() {
    const { ctx } = this;
    ctx.clearRect(0, 0, this.width, this.height);
    ctx.font = `${this.cell}px ui-monospace, "SF Mono", Menlo, Consolas, monospace`;
    ctx.textBaseline = "top";
    return this.palette(this);
  }

  render(t) {
    if (this.mode === "horizon") return this.renderHorizon(t);
    const { ctx, cols, rows, cw, ch } = this;
    const colors = this.begin();
    const calm = this.mode === "journey" ? this.calm : 1;
    const speed = this.mode === "journey" ? 0.35 + (1 - calm) * 0.9 : 0.6;
    const tt = t * speed;
    const bands = colors.bands.length;
    const shift = this.offset / ch;
    const rowShift = Math.floor(shift);
    const sub = (shift - rowShift) * ch;

    for (let y = -1; y < rows + 1; y++) {
      const fy = y + rowShift;
      const depth = Math.min(1, Math.max(0, y / rows));
      let band = -1;
      for (let x = 0; x < cols; x++) {
        let v = water(x, fy, depth, tt) * (0.18 + depth * 0.95);
        if (calm < 1) v = v * calm + chaos(x, fy, tt) * (1 - calm);
        v += this.ripple(x, y, t);
        const index = Math.min(RAMP.length - 1, Math.floor(v * RAMP.length));
        if (index <= 0) continue;
        const b = Math.min(bands - 1, Math.floor((x / cols) * bands));
        if (b !== band) {
          band = b;
          ctx.fillStyle = colors.bands[b];
        }
        ctx.fillText(RAMP[index], x * cw, y * ch - sub);
      }
    }
    if (this.mode === "journey") this.drawChores(t, calm, colors);
  }

  renderHorizon(t) {
    const { ctx, cols, rows, cw, ch, width, height } = this;
    const colors = this.begin();
    const p = this.progress;
    const horizon = Math.floor(rows * 0.6);
    const hy = horizon * ch;
    const cx = width * 0.5;
    const radius = Math.min(width * 0.5, height) * 0.17;
    // The sun climbs from below the waterline to well above it.
    const sunY = hy + radius * 1.1 - p * radius * 2.2;
    const sail = t * 0.6 + p * 9;
    let style = "";
    const paint = (fill, glyph, x, y) => {
      if (fill !== style) {
        style = fill;
        ctx.fillStyle = fill;
      }
      ctx.fillText(glyph, x * cw, y * ch);
    };

    for (let y = 0; y < rows; y++) {
      const py = y * ch + ch / 2;
      for (let x = 0; x < cols; x++) {
        const px = x * cw + cw / 2;
        if (y < horizon) {
          const d = Math.hypot(px - cx, py - sunY);
          if (d < radius) {
            const v = 1 - (d / radius) * 0.55 + Math.sin(y * 0.8 + t * 2) * 0.04;
            const glyph = SUN[Math.min(SUN.length - 1, Math.floor(v * SUN.length))];
            paint(py < sunY ? colors.sun : colors.sunLow, glyph, x, y);
          } else if (d < radius * 2.6) {
            const glow = Math.pow(1 - (d - radius) / (radius * 1.6), 2) * (0.35 + p * 0.65);
            if (hash(x, y, Math.floor(t * 3)) < glow * 0.55)
              paint(colors.halo, glow > 0.5 ? ":" : ".", x, y);
          } else if (hash(x, y, 7) > 0.988 && hash(x, y, Math.floor(t * 1.5)) > 0.25 * (1 + p)) {
            paint(colors.star, hash(x, y, 3) > 0.7 ? "+" : ".", x, y);
          }
          continue;
        }
        const depth = (y - horizon) / (rows - horizon);
        let v = water(x, y, depth, sail) * (0.25 + depth * 0.85) + this.ripple(x, y, t);
        // The sun's reflection: a wobbling column that widens toward the viewer.
        const reach = radius * (0.35 + depth * 1.5) * (0.4 + p * 0.6);
        const wobble = Math.sin(y * 1.7 + t * 3) * cw * 2 * (0.5 + depth);
        const inColumn = Math.abs(px - cx + wobble) < reach && sunY < hy + radius;
        if (inColumn && hash(x, y, Math.floor(t * 6)) > 0.35) {
          v = Math.max(v, 0.55 + 0.4 * Math.sin(x * 0.5 + t * 4));
          const index = Math.min(RAMP.length - 1, Math.floor(v * RAMP.length));
          paint(y % 2 ? colors.sun : colors.halo, RAMP[index], x, y);
          continue;
        }
        const index = Math.min(RAMP.length - 1, Math.floor(v * RAMP.length));
        if (index > 0) paint(colors.water, RAMP[index], x, y);
      }
    }
  }

  // Chores flash into the noise while the week is chaotic and fade as it calms.
  drawChores(t, calm, colors) {
    const { ctx, cols, rows, cw, ch } = this;
    const spawn = (1 - calm) * 0.9;
    if (!this.reduce && Math.random() < spawn && this.words.length < 26) {
      const text = CHORES[Math.floor(Math.random() * CHORES.length)];
      this.words.push({
        text,
        x: Math.floor(Math.random() * Math.max(1, cols - text.length)),
        y: Math.floor(Math.random() * rows),
        born: t,
        life: 0.8 + Math.random() * 1.6,
        hot: Math.random() < 0.3,
      });
    }
    if (this.reduce && this.words.length === 0 && calm < 0.5) {
      for (let i = 0; i < 14; i++) {
        const text = CHORES[i];
        this.words.push({
          text,
          x: (i * 37) % Math.max(1, cols - 16),
          y: (i * 7) % rows,
          born: t,
          life: 99,
          hot: i % 3 === 0,
        });
      }
    }
    this.words = this.words.filter((w) => t - w.born < w.life);
    for (const w of this.words) {
      const age = (t - w.born) / w.life;
      ctx.globalAlpha = Math.sin(Math.PI * Math.min(1, age)) * (1 - calm * 0.9);
      ctx.fillStyle = colors.background;
      ctx.fillRect(w.x * cw - 2, w.y * ch - 1, w.text.length * cw + 4, ch + 2);
      ctx.fillStyle = w.hot ? colors.hot : colors.word;
      ctx.fillText(w.text, w.x * cw, w.y * ch);
    }
    ctx.globalAlpha = 1;
  }
}
