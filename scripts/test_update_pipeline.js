const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const updateScript = fs.readFileSync(path.join(root, "scripts", "update_library.js"), "utf8");
const refreshScript = fs.readFileSync(path.join(root, "scripts", "refresh_open_series_seasons.ps1"), "utf8");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function firstIndexOf(source, value) {
  const index = source.indexOf(value);
  assert(index >= 0, `Expected to find ${value}.`);
  return index;
}

const firstRebuild = firstIndexOf(updateScript, 'key: "rebuildCatalog"');
const seasonRefresh = firstIndexOf(updateScript, 'key: "seasons"');
const ratingRefresh = firstIndexOf(updateScript, 'key: "ratings"');
const finalRebuild = firstIndexOf(updateScript, 'key: "publishCatalog"');

assert(
  firstRebuild < seasonRefresh && seasonRefresh < ratingRefresh && ratingRefresh < finalRebuild,
  "Full update must rebuild before season refresh, then rebuild again after cache refreshes."
);

assert(
  refreshScript.includes("$env:REFRESH_SKIP_EXISTING") &&
    refreshScript.includes("skipExisting ? items : items.filter(item => String(item.years || '').endsWith('-'))"),
  "Season refresh default should inspect every catalog row when -SkipExisting is set."
);

console.log("Update pipeline refresh order is guarded.");
