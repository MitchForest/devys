import { Effect } from "effect";
import { database, type Database } from "../data/database.ts";
import type { Scope } from "../identity/contract.ts";
import type { Runner } from "../workspace/contract.ts";
import { sha256 } from "../protocol/bytes.ts";
import { defaultLimits } from "../protocol/limits.ts";
import { rpc } from "../protocol/rpc.ts";
/** What publishing needs from the deployment: records and the public address of links. */
export interface ArtifactBindings {
  HYPERDRIVE: Database;
  PUBLIC_URL: string;
}

export function publishArtifact(
  env: ArtifactBindings,
  runner: Runner,
  scope: Scope,
  operationId: string,
  input: { path: string; filename: string; contentType: string },
) {
  const { path, filename, contentType } = input;
  return Effect.gen(function* () {
    const digest = yield* Effect.promise(() => sha256(`${scope.businessId}:${operationId}`));
    const id = `${digest.slice(0, 8)}-${digest.slice(8, 12)}-4${digest.slice(13, 16)}-a${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
    const objectKey = `${scope.businessId}/artifacts/${id}`;
    const prior = yield* database(env.HYPERDRIVE, (sql) =>
      sql.row<{ byte_length: number }>(
        "SELECT byte_length FROM artifacts WHERE business_id = $1 AND operation_id = $2",
        [scope.businessId, operationId],
      ),
    );
    const bytes = prior
      ? Number(prior.byte_length)
      : (yield* rpc(() =>
          runner(scope).exportFile(path, objectKey, defaultLimits.maxArtifactBytes),
        )).size;
    yield* database(env.HYPERDRIVE, (sql) =>
      sql.run(
        `INSERT INTO artifacts (id, business_id, operation_id, object_key, filename, content_type, byte_length)
         VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (business_id, operation_id) DO NOTHING`,
        [id, scope.businessId, operationId, objectKey, filename, contentType, bytes],
      ),
    );
    return { id, url: `${env.PUBLIC_URL}/api/artifacts/${id}`, bytes };
  });
}
export interface Artifact {
  id: string;
  filename: string;
  content_type: string;
  byte_length: number;
  created_at: string;
}
export function listArtifacts(db: Database, businessId: string, after?: string) {
  return database(db, (sql) =>
    after === undefined
      ? sql.rows<Artifact>(
          `SELECT id, filename, content_type, byte_length, created_at FROM artifacts
           WHERE business_id = $1 ORDER BY created_at DESC LIMIT 100`,
          [businessId],
        )
      : sql.rows<Artifact>(
          `SELECT id, filename, content_type, byte_length, created_at FROM artifacts
           WHERE business_id = $1 AND id > $2 ORDER BY id LIMIT 100`,
          [businessId, after],
        ),
  );
}
export function artifactLocation(db: Database, businessId: string, id: string) {
  return database(db, (sql) =>
    sql.row<{ object_key: string; filename: string; content_type: string }>(
      "SELECT object_key, filename, content_type FROM artifacts WHERE business_id = $1 AND id = $2",
      [businessId, id],
    ),
  );
}
