import { Effect } from "effect";
import type { Env } from "./env.ts";
import { codingSession } from "../apps/code/service.ts";
import { artifactLocation } from "../apps/documents/service.ts";
import { parseRef, type Ref } from "../protocol/ref.ts";
import { project } from "../work/projects.ts";
import { workItem } from "../work/service.ts";
import { businessFile } from "./files.ts";

/**
 * The ref, when it points at a record of this business: an artifact, a file in its folder, a
 * coding session, a work item or a project. Anything else (another business's record, an id
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
      default:
        return false;
    }
  };
  return (await found()) ? (value as Ref) : undefined;
}
