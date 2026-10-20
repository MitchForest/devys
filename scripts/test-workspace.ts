import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** Real Linux image smoke test; Cloudflare snapshots/egress still need live acceptance. */
const image = "devys-workspace:closeout";
const build = spawn(
  "docker",
  ["build", "--platform", "linux/amd64", "-t", image, "src/workspace/image"],
  { stdio: "inherit" },
);
await new Promise<void>((resolve, reject) => {
  build.on("error", reject);
  build.on("exit", (code) =>
    code === 0 ? resolve() : reject(new Error(`Workspace image build failed (${code})`)),
  );
});
const directory = await mkdtemp(join(tmpdir(), "devys-workspace-"));
const run = (script: string) =>
  promisify(execFile)(
    "docker",
    [
      "run",
      "--rm",
      "--platform",
      "linux/amd64",
      "--network",
      "none",
      "--mount",
      `type=bind,source=${directory},target=/workspace`,
      "--entrypoint",
      "bash",
      image,
      "-lc",
      script,
    ],
    { timeout: 30_000 },
  );
try {
  await run(`set -euo pipefail
test -x /usr/local/bin/sandbox-shim
command -v node npm python3 pip git curl timeout
mkdir -p /workspace/skills/report
cat > /workspace/skills/report/SKILL.md <<'SKILL'
---
name: report
description: Calculate a report from values.json
---
Run python3 /workspace/skills/report/report.py and read /workspace/result.txt.
SKILL
cat > /workspace/skills/report/report.py <<'PYTHON'
import json
from pathlib import Path
root = Path('/workspace')
values = json.loads((root / 'values.json').read_text())
(root / 'result.txt').write_text(str(sum(values)))
PYTHON
node -e 'require("fs").writeFileSync("/workspace/values.json", JSON.stringify([20,22]))'
timeout 5s python3 /workspace/skills/report/report.py
test "$(cat /workspace/result.txt)" = 42
`);
  await run(`set -euo pipefail
test -f /workspace/skills/report/SKILL.md
node -e 'require("fs").writeFileSync("/workspace/values.json", JSON.stringify([40,32]))'
timeout 5s python3 /workspace/skills/report/report.py
test "$(cat /workspace/result.txt)" = 72
`);
  console.log(
    "Workspace image passed: toolchain, script creation, file output and skill reuse in a fresh Linux container. No network or credentials were supplied.",
  );
} finally {
  await rm(directory, { recursive: true, force: true });
}
