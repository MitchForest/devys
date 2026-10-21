import { Schema } from "effect";
import { Timestamp } from "../../protocol/time.ts";

/** A file an employee published: its bytes are in object storage, its record here. */
export const Artifact = Schema.Struct({
  id: Schema.String,
  filename: Schema.String,
  content_type: Schema.String,
  byte_length: Schema.Number,
  created_at: Timestamp,
});
export type Artifact = typeof Artifact.Type;

/** How employees' HTML pages render (U3): the one policy every viewer applies. */

/**
 * The policy a page renders under: inline styles and scripts and data: images, nothing
 * fetched, no forms, no navigation. Viewers put it first in the document as well as on the frame.
 */
const pagePolicy =
  "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'";

/** The document a viewer loads: the policy first, then the page. */
export const sandboxed = (html: string) =>
  `<!doctype html><meta http-equiv="Content-Security-Policy" content="${pagePolicy}"><meta name="viewport" content="width=device-width, initial-scale=1">${html}`;
