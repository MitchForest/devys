import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { modelsConfig } from "../config/models.ts";
import { applicationModels, backgroundModel, modelChoice } from "../src/app/models.ts";
/** Read-only setup checks. Never print credential values. Bun loads .env. */
const photonSettings = ["PHOTON_HTTP_ADDRESS", "PHOTON_TOKEN", "PHOTON_WEBHOOK_SECRET"];
const googleSettings = [
  "GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET",
  "GOOGLE_PICKER_API_KEY",
  "GOOGLE_PROJECT_NUMBER",
  "CONNECTIONS_KEY",
];
let ready = true;
try {
  const models = applicationModels(process.env);
  for (const entry of modelsConfig.models) {
    const choice = modelChoice(entry.id);
    if (!models.getModel(choice.provider, choice.id)) throw new Error(`${entry.id} did not load`);
  }
  for (const [id, provider] of Object.entries(modelsConfig.providers)) {
    const present = Boolean(process.env[provider.key]);
    console.log(`${present ? "OK" : "MISSING"} ${provider.key} (${id} provider)`);
    ready &&= present;
  }
  backgroundModel(models, process.env);
  console.log(
    `OK ${modelsConfig.models.length} models; background ${modelsConfig.defaults.background}`,
  );
} catch (error) {
  console.log(`INVALID model configuration: ${error instanceof Error ? error.message : error}`);
  ready = false;
}
for (const name of photonSettings)
  console.log(`${process.env[name] ? "OK" : "OPTIONAL / NOT CONFIGURED"} ${name}`);
for (const name of googleSettings)
  console.log(`${process.env[name] ? "OK" : "OPTIONAL / NOT CONFIGURED"} ${name}`);
if (process.env.CONNECTIONS_KEY && !/^[a-f0-9]{64}$/.test(process.env.CONNECTIONS_KEY)) {
  console.log("INVALID CONNECTIONS_KEY: expected 32 bytes encoded as 64 lowercase hex characters");
  ready = false;
}
for (const [label, command] of [
  ["Docker engine", ["docker", "info", "--format", "{{.ServerVersion}}"]],
  ["Alchemy Cloudflare profile", ["bunx", "alchemy", "profile", "show", "--no-input"]],
] as const) {
  let ok = false;
  try {
    const { stdout } = await promisify(execFile)(command[0], command.slice(1), {
      timeout: 15_000,
      killSignal: "SIGKILL",
    });
    ok = label !== "Alchemy Cloudflare profile" || /Cloudflare .*connected/.test(stdout);
  } catch {
    /* Report only availability, never profile/credential output. */
  }
  console.log(`${ok ? "OK" : "UNAVAILABLE"} ${label}`);
  ready &&= ok;
}
console.log(
  ready
    ? "Local prerequisites present. Provider routing, quotas, and live delivery still require validation."
    : "Resolve missing prerequisites before deployment. See README.md.",
);
process.exitCode = ready ? 0 : 1;
