// The small helpers the terminal surface ported from T3 Code needs (MIT; see T3-LICENSE).
export const SELECTION_MULTI_CLICK_INTERVAL_MS = 500;

export const isMacPlatform = (
  platform: string = typeof navigator === "undefined" ? "" : navigator.platform,
) => /mac|iphone|ipad|ipod/i.test(platform);

/** Devys sets the terminal font itself, so any family it passes is accepted. */
export const isMonospaceFamily = (_family: string) => true;

export const US_SHIFTED_TO_UNSHIFTED_KEYS: ReadonlyMap<string, string> = new Map([
  ["!", "1"],
  ["@", "2"],
  ["#", "3"],
  ["$", "4"],
  ["%", "5"],
  ["^", "6"],
  ["&", "7"],
  ["*", "8"],
  ["(", "9"],
  [")", "0"],
  ["~", "`"],
  ["_", "-"],
  ["+", "="],
  ["{", "["],
  ["}", "]"],
  ["|", "\\"],
  [":", ";"],
  ['"', "'"],
  ["<", ","],
  [">", "."],
  ["?", "/"],
]);
