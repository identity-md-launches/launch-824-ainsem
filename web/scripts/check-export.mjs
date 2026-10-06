import assert from "node:assert/strict";
import { readFile, readdir, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../../dist/", import.meta.url));
const html = await readFile(path.join(root, "index.html"), "utf8");
let checked = 0;
async function checkURL(url, directory) {
  assert.ok(!/^(?:[a-z]+:|\/\/|\/)/i.test(url), `Asset must be relative: ${url}`);
  const target = path.resolve(directory, decodeURIComponent(url.split(/[?#]/)[0]));
  assert.ok(target.startsWith(root), `Asset escapes export: ${url}`);
  assert.ok((await stat(target)).isFile(), `Missing asset: ${url}`);
  checked++;
}
for (const match of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
  // The no-JavaScript fallback links to the public explorer, not a runtime asset.
  if (match[1] === "https://explorer.imd.fun/agents") continue;
  await checkURL(match[1], root);
}
const files = await readdir(root, { recursive: true });
let bytes = 0;
for (const name of files) {
  assert.ok(!/(?:^|\/)(?:node_modules|\.cache|vendor)(?:\/|$)/.test(name));
  const file = path.join(root, name);
  const info = await stat(file);
  if (!info.isFile()) continue;
  bytes += info.size;
  if (file.endsWith(".css")) {
    const css = await readFile(file, "utf8");
    for (const match of css.matchAll(/url\(["']?([^\s)"']+)["']?\)/g)) {
      await checkURL(match[1], path.dirname(file));
    }
  }
}
assert.ok(bytes < 8388608, "Export alone exceeds the submission budget");
console.log(`PASS: ${checked} relative asset references resolve; export files total ${bytes} bytes.`);
