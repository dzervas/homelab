import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const installer = fileURLToPath(new URL("./install-patchright.mjs", import.meta.url));
const helper = `async function prepareCdpPageSession(send, sessionId) {
  await Promise.all([
    send("Page.enable", void 0, sessionId).catch(() => {}),
    send("Runtime.enable", void 0, sessionId).catch(() => {}),
    send("Network.enable", void 0, sessionId).catch(() => {}),
    send("DOM.enable", void 0, sessionId).catch(() => {}),
    send("Accessibility.enable", void 0, sessionId).catch(() => {})
  ]);
  await send("Runtime.runIfWaitingForDebugger", void 0, sessionId).catch(() => {});
}
export { prepareCdpPageSession };
`;

function fixture(t, { source = helper, missing = false, wrongVersion = false, separatePlugin = false } = {}) {
  const app = mkdtempSync(join(tmpdir(), "patchright-test-"));
  t.after(() => rmSync(app, { recursive: true, force: true }));
  const write = (path, contents) => {
    mkdirSync(dirname(join(app, path)), { recursive: true });
    writeFileSync(join(app, path), contents);
  };
  // Deliberately not the current upstream version: selection must be derived.
  const version = "9.8.7";
  const store = "node_modules/.pnpm/playwright-core@9.8.7/node_modules/playwright-core";
  write("package.json", "{}");
  write(`${store}/package.json`, JSON.stringify({ name: "playwright-core", version }));
  write(`${store}/stale-file.js`, "// Must not survive replacement");
  symlinkSync(join(app, store), join(app, "node_modules/playwright-core"));
  write("dist/extensions/browser/index.js", "");
  mkdirSync(join(app, "dist/extensions/browser/node_modules"));
  if (separatePlugin) {
    write("dist/extensions/browser/node_modules/playwright-core/package.json", JSON.stringify({ name: "playwright-core", version }));
  } else {
    symlinkSync(join(app, store), join(app, "dist/extensions/browser/node_modules/playwright-core"));
  }
  write("dist/chrome-fixture.mjs", source);
  write("dist/relay.mjs", 'export const allowed = ["Runtime.enable"];\n');
  write("bin/npm", `#!${process.execPath}
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
fs.writeFileSync("npm-args.json", JSON.stringify(args));
if (${missing}) { console.error("ETARGET: no matching version"); process.exit(1); }
const root = path.join(args[args.indexOf("--prefix") + 1], "node_modules/playwright-core");
fs.mkdirSync(path.join(root, "lib"), { recursive: true });
const version = args.at(-1).split("@").at(-1);
fs.writeFileSync(path.join(root, "package.json"), JSON.stringify({ name: "patchright-core", version: ${wrongVersion ? '"0.0.1"' : "version"} }));
fs.writeFileSync(path.join(root, "index.js"), "exports.chromium = { connectOverCDP() {} };");
fs.writeFileSync(path.join(root, "lib/coreBundle.js"), "exports.getUserAgent = () => 'test';");
`);
  chmodSync(join(app, "bin/npm"), 0o755);
  const run = () => spawnSync(process.execPath, [installer], {
    cwd: app,
    env: { ...process.env, PATH: `${join(app, "bin")}:${process.env.PATH}` },
    encoding: "utf8",
  });
  return { app, run, store, version };
}

test("derives exact version, preserves pnpm links and patches only the direct enable", async (t) => {
  const { app, run, store, version } = fixture(t);
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  const args = JSON.parse(readFileSync(join(app, "npm-args.json")));
  assert.equal(args.at(-1), `playwright-core@npm:patchright-core@${version}`);
  assert.ok(args.includes("--ignore-scripts"));
  assert.equal(realpathSync(join(app, "node_modules/playwright-core")), join(app, store));
  assert.equal(JSON.parse(readFileSync(join(app, store, "package.json"))).name, "patchright-core");
  assert.equal(existsSync(join(app, store, "stale-file.js")), false);
  assert.equal(readFileSync(join(app, "dist/relay.mjs"), "utf8"), 'export const allowed = ["Runtime.enable"];\n');
  const { prepareCdpPageSession } = await import(join(app, "dist/chrome-fixture.mjs"));
  const commands = [];
  await prepareCdpPageSession(async (...args) => { commands.push(args); }, "session-1");
  assert.deepEqual(commands.map(([method]) => method), [
    "Page.enable", "Network.enable", "DOM.enable", "Accessibility.enable", "Runtime.runIfWaitingForDebugger",
  ]);
  assert.ok(commands.every(([, , session]) => session === "session-1"));
});

for (const [name, options, message] of [
  ["unpublished matching release", { missing: true }, /ETARGET/],
  ["wrong installed version", { wrongVersion: true }, /exactly match/],
  ["changed patch statement", { source: helper.replace('"Runtime.enable", void 0', '"Runtime.enable", undefined') }, /patch drift/],
  ["missing compiled helper", { source: "// moved upstream\n" }, /No compiled/],
  ["separate plugin dependency", { separatePlugin: true }, /same playwright-core/],
]) {
  test(`fails closed on ${name}`, (t) => {
    const { app, run, store } = fixture(t, options);
    const result = run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, message);
    assert.equal(JSON.parse(readFileSync(join(app, store, "package.json"))).name, "playwright-core");
    assert.equal(readFileSync(join(app, "dist/chrome-fixture.mjs"), "utf8"), options.source ?? helper);
  });
}
