import { describe, expect, it, vi } from "vitest";
import { api } from "../src/web/app/api.ts";
import { timeline } from "../src/web/app/timeline.ts";
import { mentionsIn, type ShownMessage } from "../src/conversations/contract.ts";
import { layout } from "../src/web/shell/layout.ts";
import { takeoverTitle } from "../src/web/app/names.ts";

const me = "person:p1";
const message = (
  id: number,
  author: string,
  at: string,
  kind: "message" | "event" = "message",
): ShownMessage => ({
  id: `m${id}`,
  conversation: "direct:e1",
  author,
  kind,
  text: `m${id}`,
  reply_to: null,
  mentions: [],
  via_voice: false,
  ref: null,
  replies: [],
  question: null,
  pick_many: false,
  created_at: at,
  reactions: [],
});

describe("conversation timeline, as native ChatTimeline", () => {
  it("groups consecutive messages by author and adds a heading when an hour passes", () => {
    const items = timeline(
      [
        message(1, me, "2026-10-19T10:00:00Z"),
        message(2, me, "2026-10-19T10:01:00Z"),
        message(3, "employee:e1", "2026-10-19T10:02:00Z"),
        message(4, "employee:e1", "2026-10-19T11:30:00Z"),
      ],
      [],
      me,
      new Date("2026-10-19T12:00:00Z"),
    );
    expect(items.map((i) => (i.kind === "heading" ? "heading" : i.bubble.position))).toEqual([
      "heading",
      "first",
      "last",
      "single",
      "heading",
      "single",
    ]);
    expect(items.flatMap((i) => (i.kind === "bubble" ? [i.bubble.mine] : []))).toEqual([
      true,
      true,
      false,
      false,
    ]);
  });

  it("starts a new group when another employee speaks, and events stand alone", () => {
    const items = timeline(
      [
        message(1, "employee:e1", "2026-10-19T10:00:00Z"),
        message(2, "employee:e2", "2026-10-19T10:01:00Z"),
        message(3, "system", "2026-10-19T10:01:30Z", "event"),
        message(4, "system", "2026-10-19T10:02:00Z", "event"),
      ],
      [],
      me,
      new Date("2026-10-19T12:00:00Z"),
    );
    expect(items.flatMap((i) => (i.kind === "bubble" ? [i.bubble.position] : []))).toEqual([
      "single",
      "single",
      "single",
      "single",
    ]);
  });

  it("quotes a reply only when it answers something earlier than the message above", () => {
    const items = timeline(
      [
        message(1, me, "2026-10-19T10:00:00Z"),
        { ...message(2, "employee:e1", "2026-10-19T10:01:00Z"), reply_to: "m1" },
        { ...message(3, "employee:e2", "2026-10-19T10:02:00Z"), reply_to: "m1" },
      ],
      [],
      me,
      new Date("2026-10-19T12:00:00Z"),
    );
    expect(items.flatMap((i) => (i.kind === "bubble" ? [i.bubble.replyTo] : []))).toEqual([
      null,
      null,
      "m1",
    ]);
  });

  it("puts unsent messages last as the owner's, with their delivery state and error", () => {
    const now = new Date("2026-10-19T10:00:30Z");
    const items = timeline(
      [message(1, me, "2026-10-19T10:00:00Z")],
      [{ id: "local", text: "hi", delivery: "failed", error: "Growth is paused." }],
      me,
      now,
    );
    const last = items[items.length - 1]!;
    expect(last.kind === "bubble" && last.bubble).toMatchObject({
      id: "local",
      mine: true,
      delivery: "failed",
      error: "Growth is paused.",
      position: "last",
    });
  });

  it("offers suggested replies on the latest employee message, past events, until the owner speaks", () => {
    const now = new Date("2026-10-19T10:10:00Z");
    const asked = [
      { ...message(1, "employee:e1", "2026-10-19T10:00:00Z"), replies: ["Old"] },
      { ...message(2, "employee:e2", "2026-10-19T10:01:00Z"), replies: ["Bold", "Calm"] },
      message(3, "system", "2026-10-19T10:02:00Z", "event"),
    ];
    const offered = (history: ShownMessage[], unsent: Parameters<typeof timeline>[1] = []) =>
      timeline(history, unsent, me, now).flatMap((i) =>
        i.kind === "bubble" && i.bubble.replies.length ? [[i.bubble.id, ...i.bubble.replies]] : [],
      );
    expect(offered(asked)).toEqual([["m2", "Bold", "Calm"]]);
    expect(offered([...asked, message(4, me, "2026-10-19T10:03:00Z")])).toEqual([]);
    expect(offered(asked, [{ id: "local", text: "Calm", delivery: "sending" }])).toEqual([]);
    expect(offered([...asked, message(5, "employee:e1", "2026-10-19T10:04:00Z")])).toEqual([]);
    // Devys's notice that a turn stopped offers "Ask again" while it is the latest word.
    const stopped = {
      ...message(6, "system", "2026-10-19T10:05:00Z", "event"),
      replies: ["Ask again"],
    };
    expect(offered([...asked, stopped])).toEqual([["m6", "Ask again"]]);
    expect(offered([...asked, stopped, message(7, me, "2026-10-19T10:06:00Z")])).toEqual([]);
  });

  it("carries a question card's title and pick-many only on the offered message", () => {
    const now = new Date("2026-10-19T10:10:00Z");
    const history = [
      {
        ...message(1, "employee:e1", "2026-10-19T10:00:00Z"),
        replies: ["Old"],
        question: "An older question?",
      },
      {
        ...message(2, "employee:e1", "2026-10-19T10:01:00Z"),
        replies: ["Stripe", "Ramp", "Mercury"],
        question: "Which should I connect?",
        pick_many: true,
      },
    ];
    const cards = timeline(history, [], me, now).flatMap((i) =>
      i.kind === "bubble" ? [[i.bubble.id, i.bubble.question, i.bubble.pickMany]] : [],
    );
    expect(cards).toEqual([
      ["m1", null, false],
      ["m2", "Which should I connect?", true],
    ]);
  });
});

describe("@-mentions in a draft, as the server reads them", () => {
  it("finds employees by @Name, case-insensitively, including names with spaces", () => {
    const team = [
      { id: "ops", name: "Chief of Staff" },
      { id: "g", name: "Growth" },
    ];
    expect(mentionsIn("@growth and @Chief of Staff, please", team).sort()).toEqual(["g", "ops"]);
    expect(mentionsIn("no one here", team)).toEqual([]);
  });
});

describe("workspace columns, as native WorkspaceLayout", () => {
  it("keeps the conversation at its minimum and clamps the right panel to its range", () => {
    expect(layout(1300, true, true, false, 440)).toEqual({
      sidebar: 236,
      conversation: 614,
      panel: 440,
      overlay: false,
      handle: true,
    });
    expect(layout(1300, true, true, false, 900).panel).toBe(634);
    expect(layout(1300, true, false, false, 440)).toMatchObject({ conversation: 1063, panel: 0 });
  });

  it("widens the panel to all but the conversation's minimum, and overlays it when narrow", () => {
    expect(layout(1300, true, true, true, 440)).toEqual({
      sidebar: 236,
      conversation: 420,
      panel: 634,
      overlay: false,
      handle: false,
    });
    expect(layout(900, true, true, false, 440)).toEqual({
      sidebar: 236,
      conversation: 663,
      panel: 440,
      overlay: true,
      handle: false,
    });
  });
});

describe("who has taken work over", () => {
  it("says mine only for the signed-in person", () => {
    expect(takeoverTitle(null, "p1")).toBeUndefined();
    expect(takeoverTitle("p1", "p1")).toBe("You have it");
    expect(takeoverTitle("p2", "p1")).toBe("Taken over by another person");
    expect(takeoverTitle("p2", undefined)).toBe("Taken over by another person");
    expect(takeoverTitle("p2", "p1", [{ id: "p2", display_name: "Sam" }])).toBe(
      "Taken over by Sam",
    );
  });
});

describe("a coding outcome at a glance", () => {
  it("reads the latest check, changes, pull request and commit from evidence", async () => {
    const { outcomeOf } = await import("../src/web/app/names.ts");
    const at = "2026-10-20T10:00:00Z";
    expect(outcomeOf([{ by: "employee:e1", note: "Wrote the plan", at }])).toBeUndefined();
    expect(
      outcomeOf([
        {
          by: "employee:e1",
          note: "Committed",
          at,
          commit: "a".repeat(40),
          changes: "2 files changed",
        },
        {
          by: "devys",
          note: "failed",
          at,
          commit: "a".repeat(40),
          check: { command: "bun test", exit_code: 1 },
        },
        {
          by: "devys",
          note: "passed",
          at,
          commit: "b".repeat(40),
          check: { command: "bun test", exit_code: 0 },
        },
        {
          by: "employee:e1",
          note: "Published",
          at,
          commit: "b".repeat(40),
          pull_request: "https://github.com/acme/site/pull/12",
        },
      ]),
    ).toEqual({
      deploys: [],
      commit: "bbbbbbb",
      changes: "2 files changed",
      check: { passed: true, command: "bun test" },
      pullRequest: { url: "https://github.com/acme/site/pull/12", label: "PR #12" },
    });
  });
});

describe("where coding work is live", () => {
  it("shows the latest deploy to each stage, production first", async () => {
    const { outcomeOf } = await import("../src/web/app/names.ts");
    const at = "2026-10-20T10:00:00Z";
    const outcome = outcomeOf([
      {
        by: "devys",
        note: "p1",
        at,
        commit: "a".repeat(40),
        deploy: { stage: "preview", url: "https://a.example", live: true },
      },
      {
        by: "devys",
        note: "p2",
        at,
        commit: "b".repeat(40),
        deploy: { stage: "preview", url: "https://b.example", live: false },
      },
      {
        by: "devys",
        note: "prod",
        at,
        commit: "a".repeat(40),
        deploy: { stage: "production", url: "https://acme.example", live: true },
      },
    ]);
    expect(outcome?.deploys).toEqual([
      { stage: "production", url: "https://acme.example", live: true, commit: "aaaaaaa" },
      { stage: "preview", url: "https://b.example", live: false, commit: "bbbbbbb" },
    ]);
  });
});

describe("the web client's API", () => {
  it("decodes each answer with its route's schema and names the route when it drifts", async () => {
    const answer = (body: unknown) =>
      vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json(body));
    const person = { id: "p1", display_name: "Owner" };
    answer({ person, businesses: [] });
    expect(await api.me()).toEqual({ person, businesses: [] });
    answer({ person: { id: 1 }, businesses: [] });
    await expect(api.me()).rejects.toThrow(/\/api\/me was not in the expected shape/);
    vi.restoreAllMocks();
  });
});
