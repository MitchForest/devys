import { expect, it } from "vitest";
import { captureOutput, readBounded } from "../src/protocol/bytes.ts";
const stream = (text: string) =>
  new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode(text));
      controller.close();
    },
  });
it("rejects oversized input rather than accepting a truncated document", async () => {
  await expect(readBounded(stream("abcdef"), 3)).rejects.toThrow();
});
it("retains partial command output after its limit is exceeded", async () => {
  const output = captureOutput(stream("abcdef"), 3);
  await expect(output.done).rejects.toThrow();
  expect(output.text()).toBe("abc");
});
