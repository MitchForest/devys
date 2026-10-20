import { expect, it } from "vitest";
import { withMemory, withoutMemory } from "../src/runtime/memory.ts";

it("carries business memory in the turn and strips it for history and observation", () => {
  const turn = withMemory("Book the venue for Friday.", "The owner prefers morning events.");
  expect(turn.startsWith("<business-memory>")).toBe(true);
  expect(turn.endsWith("Book the venue for Friday.")).toBe(true);
  expect(withoutMemory(turn)).toBe("Book the venue for Friday.");
  expect(withMemory("Hi", "  ")).toBe("Hi");
  expect(withoutMemory("<business-memory> unterminated")).toBe("<business-memory> unterminated");
});
