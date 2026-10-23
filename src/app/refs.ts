import { Effect } from "effect";
import type { Env } from "./env.ts";
import { codingSession } from "../apps/code/service.ts";
import { artifactLocation, artifactRecord } from "../apps/documents/service.ts";
import { sha256Bytes } from "../protocol/bytes.ts";
import { modeOf } from "./mode.ts";
import { parseRef, type Ref } from "../protocol/ref.ts";
import { project } from "../work/projects.ts";
import { workItem } from "../work/service.ts";
import { routine } from "../work/routines.ts";
import { remoteApp } from "../apps/remote.ts";
import { businessFile } from "./files.ts";

/**
 * The ref, when it points at a record of this business: an artifact, a file in its folder, a
 * coding session, a work item, a project, a routine or a remote app. Anything else (another business's record, an id
 * that names nothing) is undefined. Seeing a record here grants nothing.
 */
export async function businessRef(
  env: Env,
  businessId: string,
  value: unknown,
): Promise<Ref | undefined> {
  const parts = parseRef(value);
  if (!parts) return undefined;
  const found = async () => {
    switch (`${parts.app}/${parts.kind}`) {
      case "documents/file":
        return businessFile(env, businessId, parts.id) !== undefined;
      case "documents/artifact":
        return Boolean(
          await Effect.runPromise(artifactLocation(env.HYPERDRIVE, businessId, parts.id)),
        );
      case "code/session":
        return Boolean(
          await Effect.runPromise(codingSession(env.HYPERDRIVE, businessId, parts.id)),
        );
      case "work/item":
        return Boolean(await Effect.runPromise(workItem(env.HYPERDRIVE, businessId, parts.id)));
      case "work/project":
        return Boolean(await Effect.runPromise(project(env.HYPERDRIVE, businessId, parts.id)));
      case "work/routine":
        return Boolean(await Effect.runPromise(routine(env.HYPERDRIVE, businessId, parts.id)));
      case "team/app":
        return Boolean(await Effect.runPromise(remoteApp(env.HYPERDRIVE, businessId, parts.id)));
      default:
        return false;
    }
  };
  return (await found()) ? (value as Ref) : undefined;
}

/**
 * The hash of what a page or file says now, or undefined when it is not one of the business's: a
 * page is its latest version (publishing again under its name changes it), a file its bytes.
 */
export async function contentHash(env: Env, businessId: string, value: Ref) {
  const parts = parseRef(value);
  if (parts?.app !== "documents") return undefined;
  if (parts.kind === "artifact") {
    const record = await Effect.runPromise(artifactRecord(env.HYPERDRIVE, businessId, parts.id));
    const latest =
      record &&
      (await Effect.runPromise(artifactLocation(env.HYPERDRIVE, businessId, record.latest_id)));
    const object = latest && (await env.FILES.get(latest.object_key));
    return object ? sha256Bytes(await object.arrayBuffer()) : undefined;
  }
  const file = businessFile(env, businessId, parts.id);
  const root = modeOf(env).businessFolder(businessId);
  if (!file || !root) return undefined;
  // The runner moves bytes through R2; this copy exists only to be hashed.
  const key = `${businessId}/file-hashes/${crypto.randomUUID()}`;
  try {
    await modeOf(env)
      .runner(root)({ businessId, employeeId: "owner" })
      .exportFile(file, key, 20_000_000);
    const object = await env.FILES.get(key);
    return object ? sha256Bytes(await object.arrayBuffer()) : undefined;
  } catch {
    return undefined;
  } finally {
    await env.FILES.delete(key).catch(() => undefined);
  }
}
