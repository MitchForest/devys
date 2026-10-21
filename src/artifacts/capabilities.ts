import { artifactText, publishArtifact, saveArtifact, type ArtifactBindings } from "./service.ts";
import { Effect, Schema } from "effect";
import type { Runner } from "../workspace/contract.ts";
import { capability, CapabilityError, Invocation, FilePath } from "../protocol/capability.ts";
import { pageProblem } from "./page.ts";

/** Says in the conversation an employee is answering that it published a page. */
export type Announce = (
  invocation: { businessId: string; employeeId: string; conversation?: string },
  card: { clientId: string; text: string; ref: string },
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
      yield* Effect.promise(() =>
        announce(invocation, {
          clientId: `artifact:${saved.id}`,
          text: `Published a page: ${title}`,
          ref: `artifact:${saved.id}`,
        }),
      );
      return { id: saved.id };
    });
  return [
    capability({
      name: "artifactPage",
      description:
        "Publish a self-contained HTML page (a report, dashboard, comparison or plan) the owner sees in this conversation and can keep in a space. It renders offline and alone: inline CSS and scripts and data: images only; no forms, frames or network. Each call makes a new page; change one with artifactEdit.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        title: Title,
        html: Schema.String.check(Schema.isMaxLength(600_000)),
      }),
      output: Schema.Struct({ id: Schema.String }),
      execute: ({ title, html }) => publishPage(title, html),
    }),
    capability({
      name: "artifactEdit",
      description:
        "Change a page you published by replacing one exact piece of its HTML (it must appear once), publishing the result as the next version.",
      effect: "change",
      replay: "idempotent",
      input: Schema.Struct({
        page: Schema.String.check(Schema.isPattern(/^[0-9a-f-]{36}$/)),
        find: Schema.String.check(Schema.isMinLength(1), Schema.isMaxLength(100_000)),
        replace: Schema.String.check(Schema.isMaxLength(100_000)),
      }),
      output: Schema.Struct({ id: Schema.String }),
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
      output: Schema.Struct({ id: Schema.String, url: Schema.String, bytes: Schema.Int }),
      execute: ({ path, filename, contentType }) =>
        Effect.gen(function* () {
          const { businessId, employeeId, operationId } = yield* Invocation;
          return yield* publishArtifact(env, runner, { businessId, employeeId }, operationId, {
            path,
            filename,
            contentType,
          });
        }),
    }),
  ];
}
