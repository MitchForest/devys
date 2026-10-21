import { artifactText, publishArtifact, saveArtifact, type ArtifactBindings } from "./service.ts";
import { Effect, Schema } from "effect";
import type { Runner } from "../../workspace/contract.ts";
import {
  capability,
  CapabilityError,
  Invocation,
  FilePath,
  Text,
} from "../../protocol/capability.ts";
import { Ref, RefOf, ref } from "../../protocol/ref.ts";
import { listDrive, readDrive, writeDrive, type Drive } from "./drive.ts";
import { pageProblem } from "./page.ts";

/** Says in the conversation an employee is answering that it published a page. */
type Announce = (
  invocation: { businessId: string; employeeId: string; conversation?: string },
  card: { clientId: string; text: string; ref: Ref },
) => Promise<void>;

const Title = Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(120));
const fileName = (title: string) =>
  `${
    title
      .replace(/[^A-Za-z0-9 _.-]+/g, "")
      .trim()
      .slice(0, 100) || "page"
  }.html`;
const invalid = (message: string) => new CapabilityError({ code: "invalid_input", message });

export function artifactCapabilities(
  env: ArtifactBindings & { FILES: R2Bucket },
  runner: Runner,
  announce: Announce,
) {
  const publishPage = (title: string, html: string) =>
    Effect.gen(function* () {
      const invocation = yield* Invocation;
      const problem = pageProblem(html);
      if (problem) return yield* invalid(problem);
      const saved = yield* saveArtifact(env, invocation, invocation.operationId, {
        filename: fileName(title),
        contentType: "text/html",
        bytes: new TextEncoder().encode(html),
      });
      const published = ref("documents", "artifact", saved.id);
      // One card per page: the ref is the message's client id.
      yield* Effect.promise(() =>
        announce(invocation, {
          clientId: published,
          text: `Published a page: ${title}`,
          ref: published,
        }),
      );
      return { ref: published };
    });
  return [
    capability({
      name: "artifactPage",
      description:
        "Publish a self-contained HTML page (a report, dashboard, comparison or plan) the owner sees in this conversation and can keep in a project. It renders offline and alone: inline CSS and scripts and data: images only; no forms, frames or network. Each call makes a new page and returns its ref; change one with artifactEdit.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        title: Title,
        html: Schema.String.check(Schema.isMaxLength(600_000)),
      }),
      output: Schema.Struct({ ref: Ref }),
      execute: ({ title, html }) => publishPage(title, html),
    }),
    capability({
      name: "artifactEdit",
      description:
        "Change one of the business's pages (its ref, devys:documents/artifact/<id>) by replacing one exact piece of its HTML (it must appear once), publishing the result as the next version with a new ref.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        page: RefOf("documents", "artifact"),
        find: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(100_000)),
        replace: Schema.String.check(Schema.isMaxLength(100_000)),
      }),
      output: Schema.Struct({ ref: Ref }),
      execute: ({ page, find, replace }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          const prior = yield* artifactText(env, businessId, page);
          if (!prior || prior.content_type !== "text/html")
            return yield* invalid("That page isn't one of this business's pages.");
          const at = prior.text.indexOf(find);
          if (at < 0 || prior.text.indexOf(find, at + 1) >= 0)
            return yield* invalid("The text to find must appear exactly once in the page.");
          const title = prior.filename.replace(/\.html$/, "");
          return yield* publishPage(
            title,
            prior.text.slice(0, at) + replace + prior.text.slice(at + find.length),
          );
        }),
    }),
    capability({
      name: "publishArtifact",
      description:
        "Save a file (absolute path) as a durable private downloadable artifact. The returned link requires a member login.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        path: FilePath,
        filename: Schema.String.check(Schema.isPattern(/^[A-Za-z0-9_. -]{1,200}$/)),
        contentType: Schema.String.check(Schema.isPattern(/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/)),
      }),
      output: Schema.Struct({ ref: Ref, url: Schema.String, bytes: Schema.Int }),
      execute: ({ path, filename, contentType }) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          const saved = yield* publishArtifact(
            env,
            runner,
            { businessId, employeeId },
            operationId,
            { path, filename, contentType },
          );
          return {
            ref: ref("documents", "artifact", saved.id),
            url: saved.url,
            bytes: saved.bytes,
          };
        }),
    }),
  ];
}

/** Documents' Google Drive capabilities, through the business's Google connection. */
export function driveCapabilities(drive: Drive) {
  const google = <A>(operation: () => Promise<A>) =>
    Effect.tryPromise({
      try: operation,
      catch: (cause) =>
        new CapabilityError({
          code: "unavailable",
          message:
            cause instanceof Error &&
            /^(Connect |Choose |File |This capability |Updates support |Operation belongs|Google Drive |Connection changed)/.test(
              cause.message,
            )
              ? cause.message
              : "Google Drive unavailable; reconnect or inspect the file before repeating a write.",
        }),
    });
  const driveId = Schema.String.check(Schema.isPattern(/^[a-zA-Z0-9_-]{1,200}$/));
  const driveResult = Schema.Struct({
    id: driveId,
    status: Schema.Literals(["prepared", "uncertain", "completed"]),
    url: Schema.String,
  });
  return [
    capability({
      name: "driveList",
      description: "List Google Drive files selected for this business or created by Devys.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({}),
      output: Schema.Array(
        Schema.Struct({ id: driveId, name: Schema.String, mimeType: Schema.String }),
      ),
      execute: () =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return yield* google(() => listDrive(drive.db, businessId));
        }),
    }),
    capability({
      name: "driveRead",
      description:
        "Read a selected text file or export a selected Google Doc as plain text, up to 64 KB. Retain etag when proposing a text-file update.",
      effect: "read",
      replay: "read",
      input: Schema.Struct({ id: driveId }),
      output: Schema.Struct({
        id: driveId,
        name: Schema.String,
        mimeType: Schema.String,
        content: Text,
        etag: Schema.String,
        url: Schema.String,
      }),
      execute: ({ id }) =>
        Effect.gen(function* () {
          const { businessId } = yield* Invocation;
          return yield* google(() => readDrive(drive, businessId, id));
        }),
    }),
    capability({
      name: "driveCreate",
      description:
        "Create a plain-text file in the connected Drive. If uncertain, inspect the returned file id; do not blindly create another copy.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({
        name: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(200)),
        content: Text,
      }),
      output: driveResult,
      execute: (input) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* google(() =>
            writeDrive(drive, invocation.businessId, invocation.operationId, input, () =>
              Effect.runPromise(invocation.assertActive()),
            ),
          );
        }),
    }),
    capability({
      name: "driveUpdate",
      description:
        "Replace the contents of a selected text file using the etag from driveRead. Native Google Docs updates are not supported. Inspect an uncertain outcome before another write.",
      effect: "external",
      replay: "reconcile",
      input: Schema.Struct({
        id: driveId,
        content: Text,
        etag: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(500)),
      }),
      output: driveResult,
      execute: (input) =>
        Effect.gen(function* () {
          const invocation = yield* Invocation;
          return yield* google(() =>
            writeDrive(drive, invocation.businessId, invocation.operationId, input, () =>
              Effect.runPromise(invocation.assertActive()),
            ),
          );
        }),
    }),
  ];
}
