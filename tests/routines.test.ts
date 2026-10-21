import { expect, it } from "vitest";
import type { Trigger } from "../src/work/contract.ts";
import { describe as words, nextRun, triggerProblem, withinHours } from "../src/work/routines.ts";

const hourly = (hours?: Extract<Trigger, { kind: "cron" }>["hours"]) =>
  ({
    kind: "cron",
    expression: "0 * * * *",
    timezone: "Asia/Tokyo",
    ...(hours ? { hours } : {}),
  }) as const;

it("the next run honours active hours in the routine's time zone", () => {
  // Sunday 2026-10-25 23:30 UTC is Monday 08:30 in Tokyo.
  const after = new Date("2026-10-25T23:30:00Z");
  expect(nextRun(hourly(), after)).toBe("2026-10-26T00:00:00.000Z");
  // From 09:00 Tokyo time on Mondays only: 00:00 UTC (09:00 JST) Monday.
  const mondays = hourly({ start: "09:00", end: "18:00", days: ["mon"] });
  expect(nextRun(mondays, after)).toBe("2026-10-26T00:00:00.000Z");
  // The last Monday slot is 17:00 JST; the next is a week later at 09:00 JST.
  expect(nextRun(mondays, new Date("2026-10-26T08:00:00Z"))).toBe("2026-11-02T00:00:00.000Z");
  // Hours that span midnight.
  const night = { start: "22:00", end: "02:00" };
  expect(withinHours(night, "Asia/Tokyo", new Date("2026-10-26T14:00:00Z"))).toBe(true);
  expect(withinHours(night, "Asia/Tokyo", new Date("2026-10-26T17:00:00Z"))).toBe(false);
  expect(nextRun(hourly(night), new Date("2026-10-26T03:00:00Z"))).toBe("2026-10-26T13:00:00.000Z");
});

it("missed slots are skipped: the next run is always after now", () => {
  const weekly = { kind: "cron", expression: "0 9 * * 1", timezone: "Europe/London" } as const;
  const now = new Date("2026-10-21T12:00:00Z");
  expect(nextRun(weekly, now)).toBe("2026-10-26T09:00:00.000Z");
});

it("a schedule that can't run, or runs too often, is refused in words the employee can act on", () => {
  const now = new Date("2026-10-21T12:00:00Z");
  const cron = (expression: string, timezone = "UTC") =>
    ({ kind: "cron", expression, timezone }) as const;
  expect(triggerProblem(cron("*/30 * * * *"), now)).toBeUndefined();
  expect(triggerProblem(cron("*/5 * * * *"), now)).toBe("A routine runs at most every 15 minutes");
  expect(triggerProblem(cron("0 0 9 * * 1"), now)).toMatch(/five fields/);
  expect(triggerProblem(cron("0 9 * * 1", "Mars/Olympus"), now)).toMatch(/Unknown time zone/);
  expect(
    triggerProblem({ ...cron("0 3 * * *"), hours: { start: "09:00", end: "18:00" } }, now),
  ).toBe("The schedule never runs inside its active hours");
  expect(
    triggerProblem({ kind: "event", source: "mail", type: "received", filters: {} }, now),
  ).toBeUndefined();
});

it("a trigger reads as words", () => {
  expect(words({ kind: "cron", expression: "0 9 * * 1", timezone: "Europe/London" })).toBe(
    "At 09:00, only on Monday (Europe/London)",
  );
  expect(
    words({ kind: "event", source: "mail", type: "received", filters: { from: "a@b.test" } }),
  ).toBe('When mail reports received where from is "a@b.test"');
});
