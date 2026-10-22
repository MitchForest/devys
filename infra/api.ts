import * as Cloudflare from "alchemy/Cloudflare";
import * as Planetscale from "alchemy/Planetscale";
import { Config, Effect, Redacted } from "effect";
import type { AgentPort } from "../src/runtime/contract.ts";
import type { WorkspacePort } from "../src/workspace/contract.ts";

/**
 * Each stage owns one PlanetScale Postgres database. Alchemy applies `./migrations`
 * forward-only through its own migration role; never edit an applied migration.
 */
export const Database = Planetscale.PostgresDatabase("Database", {
  clusterSize: "PS_5",
  region: { slug: "us-east" },
  migrations: "./migrations",
});

export const Api = Cloudflare.Worker(
  "Api",
  Effect.gen(function* () {
    const database = yield* Database;
    // The Worker's role reads and writes data only; it cannot change the schema.
    const role = yield* Planetscale.PostgresRole("AppRole", {
      database,
      inheritedRoles: ["pg_read_all_data", "pg_write_all_data"],
    });
    // Caching stays off: sessions, memberships and grants must never be served stale.
    const hyperdrive = yield* Cloudflare.Hyperdrive.Connection("Hyperdrive", {
      origin: role.origin,
      caching: { disabled: true },
      dev: {
        scheme: "postgres",
        host: "127.0.0.1",
        port: 54331,
        user: "devys",
        password: Redacted.make("devys"),
        database: "devys",
        sslmode: "disable",
      },
    });
    const files = yield* Cloudflare.R2.Bucket("Files");
    return {
      main: "./src/worker.ts",
      vite: {},
      compatibilityDate: "2026-10-03",
      compatibilityFlags: ["nodejs_compat"],
      // The dispatcher: ready work items reach their employees within a minute.
      crons: ["* * * * *"],
      observability: { enabled: true, traces: { enabled: true } },
      env: {
        // The runtime contract is vendor-free; the Durable Object brand belongs to deployment.
        AGENT: Cloudflare.DurableObject<AgentPort & Rpc.DurableObjectBranded>("DevysAgent"),
        WORKSPACE: Cloudflare.Container<WorkspacePort>("Workspace", {
          className: "Workspace",
          context: "./src/workspace/image",
          schedulingPolicy: "durableObject",
          instanceType: "basic",
          maxInstances: 3,
        }),
        LOADER: Cloudflare.WorkerLoader("LOADER"),
        HYPERDRIVE: hyperdrive,
        FILES: files,
        // The key config/models.ts names for its gateway provider.
        DEVYS_MODEL_GATEWAY_KEY: yield* Config.Redacted("DEVYS_MODEL_GATEWAY_KEY").pipe(
          Config.withDefault(Redacted.make("")),
        ),
        // iMessage is optional; without these the webhook answers 503 and the apps still work.
        PHOTON_HTTP_ADDRESS: yield* Config.String("PHOTON_HTTP_ADDRESS").pipe(
          Config.withDefault(""),
        ),
        PHOTON_TOKEN: yield* Config.Redacted("PHOTON_TOKEN").pipe(
          Config.withDefault(Redacted.make("")),
        ),
        PHOTON_WEBHOOK_SECRET: yield* Config.Redacted("PHOTON_WEBHOOK_SECRET").pipe(
          Config.withDefault(Redacted.make("")),
        ),
        PHOTON_SERVER: yield* Config.String("PHOTON_SERVER").pipe(Config.withDefault("")),
        GOOGLE_CLIENT_ID: yield* Config.String("GOOGLE_CLIENT_ID").pipe(Config.withDefault("")),
        GOOGLE_CLIENT_SECRET: yield* Config.Redacted("GOOGLE_CLIENT_SECRET").pipe(
          Config.withDefault(Redacted.make("")),
        ),
        GOOGLE_PICKER_API_KEY: yield* Config.String("GOOGLE_PICKER_API_KEY").pipe(
          Config.withDefault(""),
        ),
        GOOGLE_PROJECT_NUMBER: yield* Config.String("GOOGLE_PROJECT_NUMBER").pipe(
          Config.withDefault(""),
        ),
        PUBLIC_URL: Cloudflare.Worker.URL,
        // The deployment mode (.docs/COMPONENTS.md#deployment-modes); local mode is wrangler.local.jsonc.
        DEVYS_MODE: "cloud" as "local" | "cloud",
      },
    };
  }),
);

export type Env = Cloudflare.InferEnv<typeof Api>;
