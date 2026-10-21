import { Schema } from "effect";

/**
 * A moment on the wire: ISO 8601 in UTC with milliseconds, as `Date.prototype.toISOString`
 * writes it (`2026-10-21T09:30:00.000Z`). Every timestamp a client reads has this form.
 */
export const Timestamp = Schema.String.check(
  Schema.makeFilter(
    (value) =>
      (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
        Number.isFinite(Date.parse(value))) ||
      "Expected an ISO timestamp in UTC with milliseconds",
  ),
);
