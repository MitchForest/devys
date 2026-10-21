/**
 * The Bun APIs browser-harness-js's `session.ts` uses to find a browser's DevTools port. Devys
 * connects over the pipe instead (./pipe.ts), but the file is still type-checked; the project's
 * type-check does not load Bun's own types (the Worker code runs on workerd).
 */
declare const Bun: {
  file(path: string): { text(): Promise<string>; readonly lastModified: number };
  sleep(ms: number): Promise<void>;
};
