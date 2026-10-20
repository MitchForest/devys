import { mountFaces, redrawFaces, unmountFace } from "./face.js";
import { AsciiField } from "./ascii.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const css = (el, name) => getComputedStyle(el).getPropertyValue(name).trim();

mountFaces();
new MutationObserver(redrawFaces).observe(document.documentElement, {
  attributes: true,
  attributeFilter: ["class"],
});

// Reveal on scroll: content rises 14pt and fades in, staggered by --i.
const revealer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("in");
      revealer.unobserve(entry.target);
    }
  },
  { threshold: 0.15, rootMargin: "0px 0px -6% 0px" },
);
document.querySelectorAll(".reveal, [data-ladder]").forEach((el) => revealer.observe(el));

const clamp = (v) => Math.min(1, Math.max(0, v));
// 0 when a pinned section's top reaches the viewport top, 1 when its bottom does.
const pinProgress = (section) => {
  const rect = section.getBoundingClientRect();
  return clamp(-rect.top / (rect.height - innerHeight));
};

// The trap: the week's chaos calms into water as you scroll through it.
const journey = document.querySelector("[data-journey]");
const journeyCanvas = journey.querySelector("[data-ascii]");
const asciiPalette = (el, bands) => (field) => ({
  bands: bands(el, field),
  background: css(el, "--frame"),
  word: css(el, "--ink2"),
  hot: css(el, "--amber"),
});
// Canvas fill styles get plain rgba; the tokens are hex.
const tint = (hex, alpha) => {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
};
const aurora = (el) =>
  ["--aurora-peach", "--aurora-rose", "--aurora-indigo"].map((name) => css(el, name));
const journeyField = new AsciiField(journeyCanvas, {
  mode: "journey",
  calm: 0,
  palette: asciiPalette(journey, (el, field) =>
    field.calm < 0.5
      ? [tint(css(el, "--ink3"), 0.75)]
      : aurora(el).map((hex) => tint(hex, 0.25 + field.calm * 0.45)),
  ),
});
const beats = [...journey.querySelectorAll(".beat")];
function updateJourney() {
  const progress = pinProgress(journey);
  // Chaos holds for the first two beats, then the water settles.
  journeyField.calm = clamp((progress - 0.45) / 0.4);
  // The field drifts up slower than the copy: parallax depth.
  journeyField.offset = progress * innerHeight * 0.9;
  if (reduceMotion) journeyField.render(12);
  // Beats take the stage in turn; the last holds as the water settles.
  const active = Math.min(beats.length - 1, Math.floor(progress * beats.length * 1.1));
  beats.forEach((beat, i) => {
    beat.classList.toggle("on", i === active);
    beat.classList.toggle("past", i < active);
  });
}
addEventListener("scroll", updateJourney, { passive: true });
updateJourney();

// Anywhere: pinned while an aurora sun rises out of the ASCII sea; notes arrive in turn.
const horizon = document.querySelector("[data-horizon]");
const horizonField = new AsciiField(horizon.querySelector("[data-ascii]"), {
  mode: "horizon",
  cell: 12,
  palette: (field) => {
    const [peach, rose, indigo] = aurora(horizon);
    return {
      sun: tint(peach, 0.95),
      sunLow: tint(rose, 0.9),
      halo: tint(rose, 0.55),
      water: tint(indigo, 0.35 + field.progress * 0.25),
      star: tint(css(horizon, "--ink2"), 0.8),
    };
  },
});
const horizonCopy = horizon.querySelector("[data-horizon-copy]");
const horizonNotes = [...horizon.querySelectorAll(".note")];
function updateHorizon() {
  const progress = pinProgress(horizon);
  horizonField.progress = progress;
  if (reduceMotion) horizonField.render(12);
  const enter = clamp(progress / 0.18);
  horizonCopy.style.opacity = enter.toFixed(3);
  horizonCopy.style.transform = `translateY(${(1 - enter) * 40}px)`;
  horizonNotes.forEach((note, i) => note.classList.toggle("show", progress > 0.28 + i * 0.18));
}
addEventListener("scroll", updateHorizon, { passive: true });
updateHorizon();

// Manifesto: the water scrolls at a slower depth than the tenets above it.
const manifesto = document.querySelector(".manifesto");
const manifestoField = new AsciiField(manifesto.querySelector("[data-ascii]"), {
  mode: "waves",
  cell: 14,
  palette: asciiPalette(manifesto, (el) => aurora(el).map((hex) => tint(hex, 0.55))),
});
addEventListener(
  "scroll",
  () => {
    const rect = manifesto.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > innerHeight) return;
    manifestoField.offset = -rect.top * 0.45;
    if (reduceMotion) manifestoField.render(12);
    updateManifesto();
  },
  { passive: true },
);

// Each tenet takes the stage in turn as the pinned section scrolls.
const tenets = [...manifesto.querySelectorAll(".tenets-stage li")];
const bars = [...manifesto.querySelectorAll(".manifesto-progress i")];
const count = manifesto.querySelector("[data-manifesto-count]");
function updateManifesto() {
  const active = Math.min(tenets.length - 1, Math.floor(pinProgress(manifesto) * tenets.length));
  tenets.forEach((li, i) => {
    li.classList.toggle("on", i === active);
    li.classList.toggle("past", i < active);
  });
  bars.forEach((bar, i) => bar.classList.toggle("on", i <= active));
  count.textContent = String(active + 1).padStart(2, "0");
}
updateManifesto();

// Segmented control: the selection rises out of the track and springs between options.
document.querySelectorAll("[data-seg-root]").forEach((root) => {
  const thumb = root.querySelector(".seg-thumb");
  const buttons = [...root.querySelectorAll("[data-seg]")];
  const place = (button) => {
    thumb.style.width = `${button.offsetWidth}px`;
    thumb.style.transform = `translateX(${button.offsetLeft}px)`;
  };
  const select = (button) => {
    const value = button.dataset.seg;
    for (const b of buttons) b.setAttribute("aria-selected", String(b === button));
    root.querySelectorAll("[data-seg-panel], [data-seg-text]").forEach((el) => {
      el.hidden = (el.dataset.segPanel ?? el.dataset.segText) !== value;
    });
    place(button);
    root.closest("section").dataset.mode = value;
  };
  buttons.forEach((b) => b.addEventListener("click", () => select(b)));
  addEventListener("resize", () => place(root.querySelector('[aria-selected="true"]')));
  document.fonts?.ready.then(() => place(root.querySelector('[aria-selected="true"]')));
  place(buttons[0]);

  // Show the shift once on its own, the first time it scrolls into view.
  if (!("segAuto" in root.dataset)) return;
  const auto = new IntersectionObserver(
    ([entry]) => {
      if (!entry.isIntersecting) return;
      auto.disconnect();
      if (!reduceMotion) setTimeout(() => select(buttons[1]), 1800);
    },
    { threshold: 0.6 },
  );
  auto.observe(root);
});

// Decisions: Face ID scan, then the card seals and the chip settles into Done.
// A decision shown on several surfaces (data-sync) seals on all of them at once.
function approve(decision) {
  if (decision.classList.contains("sealed") || decision.classList.contains("signing")) return;
  const copies = decision.dataset.sync
    ? [...document.querySelectorAll(`[data-sync="${decision.dataset.sync}"]`)]
    : [decision];
  decision.classList.add("signing");
  setTimeout(
    () => {
      decision.classList.remove("signing");
      for (const copy of copies) seal(copy);
      setTimeout(() => copies.forEach(reset), 5200);
    },
    reduceMotion ? 150 : 900,
  );
}

function seal(decision) {
  decision.classList.add("sealed");
  const chip = decision.querySelector("[data-chip]");
  if (chip) {
    chip.dataset.was = chip.className;
    chip.className = chip.className.replace("chip-needs", "chip-done");
    chip.innerHTML =
      '<svg class="glyph"><use href="#i-check" /></svg><span>Approved · signed</span>';
  }
  celebrate(decision);
}

function reset(decision) {
  decision.classList.remove("sealed");
  const chip = decision.querySelector("[data-chip]");
  if (chip?.dataset.was) {
    chip.className = chip.dataset.was;
    chip.innerHTML = '<svg class="glyph"><use href="#i-excl" /></svg><span>Needs approval</span>';
  }
}

// One celebration per verified result: nearby waiting faces flash joy.
function celebrate(decision) {
  const scope = decision.closest(".iphone, .mac, .step, .authority-card, .surface");
  const faces = scope?.querySelectorAll('canvas.face[data-mood="waiting"]') ?? [];
  faces.forEach((face) => {
    face.dataset.mood = "celebrate";
    setTimeout(() => (face.dataset.mood = "waiting"), 2400);
  });
}

document.querySelectorAll("[data-approve]").forEach((button) => {
  button.addEventListener("click", () => approve(button.closest("[data-decision]")));
});

// Hero: the push arrives, then the phone's decision signs itself once.
const push = document.querySelector("[data-push]");
const heroDecision = document.querySelector(".iphone [data-decision]");
setTimeout(() => push.classList.add("show"), reduceMotion ? 0 : 1400);
if (!reduceMotion) {
  setTimeout(() => push.classList.remove("show"), 4600);
  setTimeout(() => approve(heroDecision), 5200);
}

// Inspector: Operations' answer streams in with a soft shimmer.
document.querySelectorAll("[data-stream]").forEach((el) => {
  const text = el.textContent.trim().replace(/\s+/g, " ");
  if (reduceMotion) return;
  el.textContent = "";
  const io = new IntersectionObserver(
    ([entry]) => {
      if (!entry.isIntersecting) return;
      io.disconnect();
      const span = document.createElement("span");
      span.className = "shimmer";
      const caret = document.createElement("i");
      caret.className = "caret";
      el.append(span, caret);
      let i = 0;
      const timer = setInterval(() => {
        i = Math.min(text.length, i + 2 + Math.floor(Math.random() * 3));
        span.textContent = text.slice(0, i);
        if (i >= text.length) {
          clearInterval(timer);
          caret.remove();
          span.className = "";
        }
      }, 45);
    },
    { threshold: 0.6 },
  );
  io.observe(el);
});

// How it works, step two: Engineering finishes, celebrates, and starts the next thing.
const cycle = document.querySelector("[data-cycle]");
if (cycle && !reduceMotion) {
  const face = cycle.querySelector("[data-cycle-face]");
  const text = cycle.querySelector("[data-cycle-text]");
  const chip = cycle.querySelector("[data-cycle-chip]");
  const states = [
    ["working", "Deploying a preview of the pricing page", "progress"],
    ["celebrate", "Preview deployed and verified", "done"],
    ["thinking", "Reading the checkout bug report", "progress"],
    ["working", "Fixing the checkout bug, tests running", "progress"],
    ["celebrate", "Fix verified, waiting for release window", "done"],
  ];
  const chipHTML = {
    progress:
      '<svg class="glyph spin" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.4" /></svg>In progress',
    done: '<svg class="glyph"><use href="#i-check" /></svg>Done',
  };
  let index = 0;
  setInterval(() => {
    index = (index + 1) % states.length;
    const [mood, line, tone] = states[index];
    face.dataset.mood = mood;
    text.textContent = line;
    chip.className = `chip chip-${tone}`;
    chip.innerHTML = chipHTML[tone];
  }, 3200);
}

// Scale the Mac window to fit its column, keeping native proportions.
document.querySelectorAll("[data-fit]").forEach((fit) => {
  const inner = fit.querySelector("[data-fit-inner]");
  const resize = () => {
    const scale = Math.min(1, fit.clientWidth / inner.offsetWidth);
    inner.style.transform = `scale(${scale})`;
    fit.style.height = `${inner.offsetHeight * scale}px`;
    if (scale === 1) inner.style.marginInline = `${(fit.clientWidth - inner.offsetWidth) / 2}px`;
    else inner.style.marginInline = "0";
  };
  new ResizeObserver(resize).observe(fit);
});

// Navigation glass firms up once the page scrolls and turns dark over dark sections.
const nav = document.querySelector("[data-nav]");
const darkSections = [...document.querySelectorAll(".scope-dark")];
function updateNav() {
  nav.classList.toggle("scrolled", scrollY > 40);
  const y = nav.getBoundingClientRect().bottom - 20;
  nav.classList.toggle(
    "on-dark",
    darkSections.some((section) => {
      const rect = section.getBoundingClientRect();
      return rect.top <= y && rect.bottom >= y;
    }),
  );
}
addEventListener("scroll", updateNav, { passive: true });
updateNav();

// Voice: hold the hotkey, words arrive with the unsettled tail dimmed, then settle.
const voice = document.querySelector("[data-voice]");
if (voice && !reduceMotion) {
  const finalText = voice.querySelector("[data-voice-final]");
  const tail = voice.querySelector("[data-voice-tail]");
  const phrases = [
    "Tell Growth to send it",
    "What's blocking launch?",
    "Ask Engineering to ship the fix",
  ];
  let phrase = 0;
  const speak = () => {
    const words = phrases[phrase].split(" ");
    phrase = (phrase + 1) % phrases.length;
    voice.classList.add("listening");
    finalText.textContent = "";
    tail.textContent = "";
    words.forEach((_, i) => {
      setTimeout(
        () => {
          finalText.textContent = words.slice(0, Math.max(0, i - 1)).join(" ");
          tail.textContent = words.slice(Math.max(0, i - 1), i + 1).join(" ");
        },
        380 * (i + 1),
      );
    });
    setTimeout(
      () => {
        finalText.textContent = words.join(" ");
        tail.textContent = "";
        voice.classList.remove("listening");
      },
      380 * (words.length + 1),
    );
  };
  speak();
  setInterval(speak, 4600);
}

// Hiring: a role template fills in the employee, its model and its starting access.
const hire = document.querySelector("[data-hire]");
if (hire) {
  const templates = {
    engineering: {
      name: "Engineering",
      role: "Builds, verifies and deploys the product",
      face: ["green", "hexagon", 3],
      model: "GPT-6.1 Sol",
      price: "~6¢ a turn",
      access: [
        ["check", "ok", "Edit the repository", ""],
        ["check", "ok", "Deploy previews", ""],
        ["faceid", "ask", "Deploy production", "asks first"],
        ["money", "no", "Spend money", "never"],
      ],
    },
    growth: {
      name: "Growth",
      role: "Measurement, PR and campaigns",
      face: ["orange", "blob", 11],
      model: "Claude Opus 5.5",
      price: "~4¢ a turn",
      access: [
        ["check", "ok", "Read Analytics and Search Console", ""],
        ["faceid", "ask", "Email suppliers", "asks first"],
        ["sliders", "no", "Run ads", "not granted"],
        ["money", "no", "Spend money", "never"],
      ],
    },
    ops: {
      name: "Business Ops",
      role: "Accounts, purchases and suppliers",
      face: ["purple", "capsule", 5],
      model: "Gemini 4 Argon",
      price: "~3¢ a turn",
      access: [
        ["check", "ok", "Prepare purchases", ""],
        ["faceid", "ask", "Pay with the company card", "asks first"],
        ["faceid", "ask", "Create accounts", "asks first"],
        ["sliders", "no", "Change billing plans", "not granted"],
      ],
    },
  };
  let face = hire.querySelector("[data-hire-face]");
  const access = hire.querySelector("[data-hire-access]");
  const fill = (key) => {
    const t = templates[key];
    hire.querySelector("[data-hire-name]").textContent = t.name;
    hire.querySelector("[data-hire-role]").textContent = t.role;
    hire.querySelector("[data-hire-model]").textContent = t.model;
    hire.querySelector("[data-hire-price]").textContent = t.price;
    access.innerHTML = t.access
      .map(
        ([icon, tone, text, note]) =>
          `<li><svg class="ico ${tone}"><use href="#i-${icon}" /></svg>${text}${note ? `<em>${note}</em>` : ""}</li>`,
      )
      .join("");
    // A new hire is a new Face: swap the canvas so the renderer mounts it fresh.
    const [palette, shape, seed] = t.face;
    if (face.dataset.palette !== palette) {
      const next = face.cloneNode();
      Object.assign(next.dataset, { palette, shape, seed: String(seed), mood: "celebrate" });
      delete next.dataset.mounted;
      face.replaceWith(next);
      unmountFace(face);
      face = next;
      mountFaces(hire);
      setTimeout(() => (next.dataset.mood = "idle"), 1400);
    }
  };
  const buttons = [...hire.querySelectorAll("[data-template]")];
  buttons.forEach((button) =>
    button.addEventListener("click", () => {
      buttons.forEach((b) => b.setAttribute("aria-selected", String(b === button)));
      hire.classList.add("swapping");
      setTimeout(() => {
        fill(button.dataset.template);
        hire.classList.remove("swapping");
      }, 200);
    }),
  );
  fill("growth");
}

// Engineering: the diff writes itself, tests tick up, then it waits for you.
const assignment = document.querySelector("[data-assignment]");
if (assignment) {
  const lines = [...assignment.querySelectorAll("[data-diff] span")];
  const count = assignment.querySelector("[data-tests-count]");
  const chip = assignment.querySelector("[data-assignment-chip]");
  const engineer = assignment.querySelector("[data-assignment-face]");
  const ready = () => {
    count.textContent = "48";
    chip.className = "chip chip-needs";
    chip.innerHTML = '<svg class="glyph"><use href="#i-excl" /></svg>Ready for you';
    engineer.dataset.mood = "waiting";
  };
  const run = new IntersectionObserver(
    ([entry]) => {
      if (!entry.isIntersecting) return;
      run.disconnect();
      if (reduceMotion) {
        assignment.querySelector("[data-diff]").classList.add("static");
        return ready();
      }
      lines.forEach((line, i) => setTimeout(() => line.classList.add("in"), 250 + i * 260));
      const start = 250 + lines.length * 260;
      for (let n = 1; n <= 12; n++) {
        setTimeout(() => (count.textContent = String(n * 4)), start + n * 70);
      }
      setTimeout(ready, start + 1000);
    },
    { threshold: 0.4 },
  );
  run.observe(assignment);
  assignment.querySelector("[data-accept]").addEventListener("click", (event) => {
    assignment.classList.add("accepted");
    event.currentTarget.textContent = "Accepted · deploying";
    chip.className = "chip chip-done";
    chip.innerHTML = '<svg class="glyph"><use href="#i-check" /></svg>Accepted';
    engineer.dataset.mood = "celebrate";
  });
}

// Live session: take over and the employee pauses; hand back and it resumes.
const live = document.querySelector("[data-live]");
if (live) {
  const button = live.querySelector("[data-takeover]");
  const status = live.querySelector("[data-live-status]");
  const employee = live.querySelector("[data-live-face]");
  button.addEventListener("click", () => {
    const taking = !live.classList.contains("taken");
    live.classList.toggle("taken", taking);
    button.textContent = taking ? "Hand back" : "Take over";
    button.className = `btn btn-compact ${taking ? "btn-aurora" : "btn-raised"}`;
    status.innerHTML = taking
      ? "<b>You</b> have control. Business Ops is paused on this."
      : "<b>Business Ops</b> is buying acme.example";
    employee.dataset.mood = taking ? "waiting" : "working";
  });
}

// The brand mark lives like an employee: it blinks and glances on its own, now and then
// thinks, works or waits, and lights up when you point at it.
document.querySelectorAll("canvas.face[data-brand]").forEach((mark) => {
  if (reduceMotion) return;
  const moods = ["thinking", "working", "waiting", "celebrate", "listening"];
  let settle;
  const feel = (mood, hold) => {
    clearTimeout(settle);
    mark.dataset.mood = mood;
    settle = setTimeout(() => (mark.dataset.mood = "idle"), hold);
  };
  const wander = () => {
    feel(moods[Math.floor(Math.random() * moods.length)], 1400 + Math.random() * 1200);
    setTimeout(wander, 5000 + Math.random() * 5000);
  };
  setTimeout(wander, 3000 + Math.random() * 3000);
  mark.closest("a, .nav-brand")?.addEventListener("pointerenter", () => feel("celebrate", 1200));
});
