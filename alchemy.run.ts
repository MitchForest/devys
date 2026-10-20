import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Planetscale from "alchemy/Planetscale";
import { Effect, Layer } from "effect";
import { Api, Database } from "./infra/api.ts";

export default Alchemy.Stack(
  "devys",
  {
    providers: Layer.mergeAll(Cloudflare.providers(), Planetscale.providers()),
    state: Cloudflare.state(),
  },
  Effect.gen(function* () {
    const api = yield* Api;
    return { api: api.url, database: (yield* Database).name };
  }),
);
