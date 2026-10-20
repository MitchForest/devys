import { describe, expect, it } from "vitest";
import { timeline } from "../src/web/app/timeline.ts";
import { mentionsIn } from "../src/web/app/conversation.ts";
import { layout } from "../src/web/shell/layout.ts";
import type { ShownMessage } from "../src/web/app/api.ts";

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
});

describe("@-mentions in a draft, as the server reads them", () => {
  it("finds employees by @Name, case-insensitively, including names with spaces", () => {
    const team = [
      { id: "ops", name: "Head of Operations" },
      { id: "g", name: "Growth" },
    ];
    expect(mentionsIn("@growth and @Head of Operations, please", team).sort()).toEqual([
      "g",
      "ops",
    ]);
    expect(mentionsIn("no one here", team)).toEqual([]);
  });
});

describe("workspace columns, as native WorkspaceLayout", () => {
  it("fits sidebar, page and inspector, clamping the inspector to its range", () => {
    expect(layout(1300, true, true, false, 320)).toEqual({
      sidebar: 236,
      page: 734,
      inspector: 320,
      showsHandle: true,
    });
    expect(layout(1300, true, true, false, 900).inspector).toBe(634);
  });

  it("lets the page win when too narrow, and expands the conversation over the page", () => {
    expect(layout(900, true, true, false, 320)).toEqual({
      sidebar: 236,
      page: 663,
      inspector: 0,
      showsHandle: false,
    });
    expect(layout(900, false, true, true, 320)).toEqual({
      sidebar: 0,
      page: 0,
      inspector: 900,
      showsHandle: false,
    });
  });
});
