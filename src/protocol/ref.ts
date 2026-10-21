import { Schema } from "effect";

/**
 * The record kinds anything can point at, by the app that owns each: one closed list
 * (.docs/APPS_AND_CAPABILITIES.md#record-and-ref). Each is listed in its app's `records`.
 */
export const refKinds = {
  documents: ["artifact", "file"],
  code: ["session"],
  work: ["item", "project"],
} as const;

export type RefApp = keyof typeof refKinds;
export type RefKind<A extends RefApp = RefApp> = (typeof refKinds)[A][number];

/** A ref taken apart: its app, its kind and its (decoded) id. */
export type RefParts = { [A in RefApp]: { app: A; kind: RefKind<A>; id: string } }[RefApp];

/** The ref of one record. A file's id is its absolute path. */
export const ref = <A extends RefApp>(app: A, kind: RefKind<A>, id: string) =>
  `devys:${app}/${kind}/${encodeURIComponent(id)}` as Ref;

/**
 * The parts of a ref, or undefined for anything else: an unknown app or kind, an empty id,
 * or an id not in the encoding `ref` gives it.
 */
export function parseRef(value: unknown): RefParts | undefined {
  if (typeof value !== "string") return undefined;
  const [, app, kind, encoded] = /^devys:([a-z]+)\/([a-z]+)\/([^/]+)$/.exec(value) ?? [];
  if (!app || !kind || !encoded || !Object.hasOwn(refKinds, app)) return undefined;
  if (!(refKinds[app as RefApp] as readonly string[]).includes(kind)) return undefined;
  let id: string;
  try {
    id = decodeURIComponent(encoded);
  } catch {
    return undefined;
  }
  if (encodeURIComponent(id) !== encoded) return undefined;
  return { app, kind, id } as RefParts;
}

/**
 * A record's address, `devys:<app>/<kind>/<id>` with the id percent-encoded. Marked pure so
 * a client that only parses refs leaves the schema library out of its bundle.
 */
export const Ref = /*#__PURE__*/ Schema.String.check(
  /*#__PURE__*/ Schema.isMaxLength(2048),
  /*#__PURE__*/ Schema.isPattern(/^devys:[a-z]+\/[a-z]+\/[^/]+$/),
  /*#__PURE__*/ Schema.makeFilter((value) => parseRef(value) !== undefined),
).pipe(/*#__PURE__*/ Schema.brand("Ref"));
export type Ref = typeof Ref.Type;
