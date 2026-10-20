import { expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
const read = (path: string) => readFileSync(path, "utf8");
function files(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? files(join(directory, entry.name))
      : /\.tsx?$/.test(entry.name)
        ? [join(directory, entry.name)]
        : [],
  );
}
it("only application wiring selects the memory engine; consumers use its contract", () => {
  for (const path of files("src")) {
    const text = read(path);
    if (path.startsWith("src/memory/") || path === "src/app/memory.ts") continue;
    expect(text, `${path} reaches into the memory implementation`).not.toMatch(
      /from ["'][^"']*memory\/(?:service|store|consolidation)\.ts/,
    );
    expect(text, `${path} reads memory tables directly`).not.toMatch(
      /(?:FROM|INTO|UPDATE)\s+(?:memories|memory_sources|memory_state|memory_links)\b/i,
    );
  }
  expect(read("src/memory/contract.ts")).not.toMatch(/D1Database|Env|pi-durable|cloudflare|photon/);
});
it("HTTP adapters and application wiring do not own SQL or provider-specific agent input", () => {
  for (const path of [
    ...files("src/app"),
    "src/worker.ts",
    "src/host.ts",
    "src/identity/http.ts",
    "src/memory/http.ts",
  ])
    expect(read(path), path).not.toMatch(sqlStatement);
  expect(read("src/runtime/agent.ts")).not.toMatch(/channels\/(?:photon|input)\.ts/);
});

const sqlStatement =
  /\b(?:SELECT\s[\s\S]{0,200}?\bFROM|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b/;

// Adding a component is an explicit decision: extend this list and the component map.
const components = [
  "app",
  "artifacts",
  "authority",
  "channels",
  "connections",
  "conversations",
  "data",
  "delegates",
  "egress",
  "identity",
  "memory",
  "protocol",
  "runtime",
  "surfaces",
  "terminal",
  "web",
  "work",
  "workspace",
];
it("the component list is explicit", () => {
  const present = readdirSync("src", { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  expect(present).toEqual(components);
});

/** Table owners come from the `-- component` headings in the migrations. */
function tableOwners() {
  const owners = new Map<string, string>();
  for (const migration of readdirSync("migrations")) {
    let owner = "";
    for (const line of read(join("migrations", migration, "migration.sql")).split("\n")) {
      const heading = /^-- (\w+)\b/.exec(line)?.[1];
      if (heading && components.includes(heading)) owner = heading;
      const table = /^CREATE TABLE (\w+)/.exec(line)?.[1];
      if (table) owners.set(table, owner);
      // A later migration may change a table only under its owner's heading (migrations from
      // before headings were required name no owner and are never edited).
      const altered = /^ALTER TABLE (\w+)/.exec(line)?.[1];
      if (altered && owner && owners.get(altered) !== owner)
        throw new Error(
          `${migration} alters ${owners.get(altered)}'s table ${altered} under ${owner}`,
        );
    }
  }
  return owners;
}
it("every migration since headings were introduced names its component first", () => {
  for (const migration of readdirSync("migrations").filter((name) => name >= "20261020020000"))
    expect(components, `${migration} starts with a component heading`).toContain(
      /^-- (\w+)/.exec(read(join("migrations", migration, "migration.sql")))?.[1],
    );
});

it("each table is read and written only by the component that owns it", () => {
  const owners = tableOwners();
  expect(owners.size).toBeGreaterThan(10);
  expect([...owners.values()].every(Boolean), "every table sits under a component heading").toBe(
    true,
  );
  for (const path of files("src")) {
    const text = read(path);
    for (const [table, owner] of owners) {
      if (component(path) === owner) continue;
      expect(text, `${path} touches ${owner}'s table ${table}`).not.toMatch(
        new RegExp(`\\b(?:FROM|INTO|UPDATE|JOIN)\\s+${table}\\b`, "i"),
      );
    }
  }
});

it("no ORMs, workflow engines, dependency-injection containers or event buses", () => {
  const manifest = JSON.parse(read("package.json")) as Record<string, Record<string, string>>;
  const dependencies = Object.keys({ ...manifest.dependencies, ...manifest.devDependencies });
  const forbidden =
    /^(?:drizzle-orm|drizzle-kit|kysely|prisma|@prisma\/.*|typeorm|sequelize|@mikro-orm\/.*|@effect\/sql.*|inversify|tsyringe|@nestjs\/.*|xstate|bullmq|inngest|@temporalio\/.*|eventemitter2|rxjs)$/;
  expect(dependencies.filter((name) => forbidden.test(name))).toEqual([]);
});

// Shared kernel: importable everywhere. Wiring: may import any component internals.
const shared = ["src/protocol/", "src/data/"];
const wiring = (path: string) =>
  path.startsWith("src/app/") || path === "src/worker.ts" || path === "src/host.ts";
const component = (path: string) => /^src\/([^/]+)\//.exec(path)?.[1];
const imports = (path: string) =>
  [...read(path).matchAll(/(?:from|import)\s*\(?\s*["']([^"']+)["']/g)].map((match) => match[1]!);
const resolve = (from: string, target: string) => join(from, "..", target).replaceAll("\\", "/");

it("components reach each other only through contract.ts; only wiring selects adapters", () => {
  for (const path of files("src")) {
    if (wiring(path)) continue;
    const own = component(path);
    for (const target of imports(path).filter((value) => value.startsWith("."))) {
      const resolved = resolve(path, target);
      if (!resolved.startsWith("src/") || shared.some((prefix) => resolved.startsWith(prefix)))
        continue;
      expect(wiring(resolved), `${path} imports application wiring ${resolved}`).toBe(false);
      // The web client renders document surfaces directly; they are its UI library.
      if (own === "web" && component(resolved) === "surfaces") continue;
      if (component(resolved) !== own)
        expect(resolved, `${path} reaches into ${resolved}`).toMatch(/^src\/[^/]+\/contract\.ts$/);
    }
  }
});

it("only wiring reads the deployment files; components declare the bindings they use", () => {
  for (const path of files("src")) {
    if (wiring(path)) continue;
    for (const target of imports(path).filter((value) => value.startsWith(".")))
      expect(resolve(path, target), `${path} imports ${target}`).toMatch(/^src\//);
  }
});

it("a contract's functions and values are used by another component or wiring", () => {
  const unused: string[] = [];
  for (const contract of files("src").filter((path) => path.endsWith("/contract.ts"))) {
    const owner = component(contract);
    const exported = [
      ...read(contract).matchAll(
        // Types also describe records wiring receives from services, so only values are checked.
        /^export (?:declare )?(?:const|function|class) (\w+)/gm,
      ),
    ].map((match) => match[1]!);
    const used = new Set<string>();
    for (const path of [...files("src"), ...files("infra")]) {
      if (component(path) === owner) continue;
      for (const match of read(path).matchAll(
        /import\s+(?:type\s+)?\{([^}]*)\}\s+from\s+["']([^"']+)["']/g,
      ))
        if (resolve(path, match[2]!) === contract)
          for (const name of match[1]!.split(","))
            used.add(
              name
                .replace(/^\s*type\s+/, "")
                .split(/\s+as\s+/)[0]!
                .trim(),
            );
    }
    // A name used only by its own component belongs in an internal module, unless another
    // export's signature names it (a port's argument types are part of the port).
    const text = read(contract);
    const internal = exported.filter(
      (name) => !used.has(name) && text.match(new RegExp(`\\b${name}\\b`, "g"))!.length === 1,
    );
    unused.push(...internal.map((name) => `${contract}: ${name}`));
  }
  expect(unused, "contract exports no other component uses").toEqual([]);
});

it("document surfaces depend on no component, so every client can host them", () => {
  for (const path of files("src/surfaces"))
    for (const target of imports(path).filter((value) => value.startsWith(".")))
      expect(resolve(path, target), `${path} imports ${target}`).toMatch(/^src\/surfaces\//);
});

it("contracts are vendor-free and depend only on other contracts", () => {
  const contracts = files("src").filter((path) => path.endsWith("/contract.ts"));
  expect(contracts.length).toBeGreaterThan(4);
  for (const path of contracts) {
    const text = read(path);
    expect(text, `${path} owns SQL`).not.toMatch(sqlStatement);
    for (const target of imports(path)) {
      if (target === "effect") continue;
      expect(target, `${path} imports ${target}`).toMatch(/^\.\.?\//);
      const resolved = resolve(path, target);
      expect(
        resolved.endsWith("/contract.ts") || shared.some((prefix) => resolved.startsWith(prefix)),
        `${path} imports non-contract ${resolved}`,
      ).toBe(true);
    }
  }
});
