// Run from the upstream /app directory during the image build.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const app = process.cwd();
const require = createRequire(join(app, "package.json"));
const browserRequire = createRequire(join(app, "dist/extensions/browser/index.js"));
const originalManifest = realpathSync(require.resolve("playwright-core/package.json"));
assert.equal(
  realpathSync(browserRequire.resolve("playwright-core/package.json")),
  originalManifest,
  "Browser plugin and Gateway must resolve the same playwright-core installation",
);
const original = dirname(originalManifest);
const { name, version } = JSON.parse(readFileSync(originalManifest, "utf8"));
assert.equal(name, "playwright-core", "Expected an unmodified upstream image");
assert.match(version, /^\d+\.\d+\.\d+(?:-[\w.-]+)?$/, "Expected an exact installed version");

// Patch the shipped JavaScript, not the unexecuted TypeScript sources. Match the
// complete known helper so an upstream implementation change fails the build.
const helper = /async function prepareCdpPageSession\(send, sessionId\) \{[\s\S]*?\n\}/g;
const enable = /^\s*send\("Runtime\.enable", void 0, sessionId\)\.catch\(\(\) => \{\}\),\n/gm;
const patches = [];
for (const file of readdirSync(join(app, "dist"), { recursive: true })) {
  if (!/\.(?:mjs|cjs|js)$/.test(file)) continue;
  const path = join(app, "dist", file);
  const source = readFileSync(path, "utf8");
  const patched = source.replace(helper, (body) => {
    assert.equal([...body.matchAll(enable)].length, 1, `Runtime.enable patch drift in ${file}`);
    return body.replace(enable, "");
  });
  if (patched !== source) patches.push([path, patched]);
}
assert.ok(patches.length > 0, "No compiled prepareCdpPageSession helper found; review upstream changes");

const staging = mkdtempSync(join(tmpdir(), "openclaw-patchright-"));
try {
  // Exact version, derived from upstream. npm exits nonzero if it is unpublished:
  // never use latest, a version range, or a fallback to stock Playwright.
  execFileSync("npm", [
    "install", "--prefix", staging, "--omit=dev", "--ignore-scripts",
    "--no-audit", "--no-fund", "--save-exact",
    `playwright-core@npm:patchright-core@${version}`,
  ], { stdio: "inherit" });
  const replacement = join(staging, "node_modules/playwright-core");
  const installed = JSON.parse(readFileSync(join(replacement, "package.json"), "utf8"));
  assert.equal(installed.name, "patchright-core");
  assert.equal(installed.version, version, "Patchright must exactly match upstream Playwright");

  // Replace the real pnpm store directory, retaining all root/plugin symlinks.
  // Installing into /app with npm would rewrite the upstream dependency tree.
  rmSync(original, { recursive: true });
  cpSync(replacement, original, { recursive: true });
  for (const [path, patched] of patches) writeFileSync(path, patched);

  for (const loader of [require, browserRequire]) {
    assert.equal(loader("playwright-core/package.json").name, "patchright-core");
    assert.equal(loader("playwright-core/package.json").version, version);
    assert.equal(typeof loader("playwright-core").chromium.connectOverCDP, "function");
    assert.equal(typeof loader("playwright-core/lib/coreBundle").getUserAgent, "function");
  }
  console.log(`Installed Patchright ${version}; patched ${patches.length} compiled browser bundle(s)`);
} finally {
  rmSync(staging, { recursive: true, force: true });
}
