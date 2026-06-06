const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const requiredPublicFiles = [
  "api/series-state-store.js",
  "api/series-state-handler.js",
  "api/series-state.js",
  "api/series-state/[imdbId].js",
  "series_library.html",
  "series_library.css",
  "series_library.js",
  "series_library_data.json",
  "series_library_data_client.js",
  "series_library_details.json",
  "series_library_rendering.js",
];
const requiredIgnoredPaths = [
  "node_modules",
  ".git",
  ".vercel",
  "imdb_*_catalog_cache",
  "imdb_*_year_files_primary_origin",
  "scripts/.generated",
  "series_library.db",
  "series_library.db-shm",
  "series_library.db-wal",
  "series_user_state.db",
  "series_user_state.db-shm",
  "series_user_state.db-wal",
];

function readText(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8").replace(/^\uFEFF/, "");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function ignorePatternMatches(pattern, file) {
  const escaped = pattern
    .split("*")
    .map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
    .join(".*");
  return new RegExp(`^${escaped}$`).test(file);
}

function isIgnored(file, patterns) {
  return patterns.some((pattern) => ignorePatternMatches(pattern, file));
}

const vercelConfig = JSON.parse(readText("vercel.json"));
const vercelIgnore = readText(".vercelignore")
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith("#"));
const html = readText("series_library.html");

for (const file of requiredPublicFiles) {
  assert(fs.existsSync(path.join(root, file)), `Missing public deploy file: ${file}`);
  assert(!isIgnored(file, vercelIgnore), `Public deploy file is ignored by .vercelignore: ${file}`);
}

for (const ignoredPath of requiredIgnoredPaths) {
  assert(vercelIgnore.includes(ignoredPath), `.vercelignore should exclude ${ignoredPath}`);
}

assert(
  Array.isArray(vercelConfig.rewrites) &&
    vercelConfig.rewrites.some((rewrite) => rewrite.source === "/" && rewrite.destination === "/series_library.html"),
  "vercel.json should rewrite / to /series_library.html"
);

for (const jsonFile of ["series_library_data.json", "series_library_details.json"]) {
  const hasHeader = (vercelConfig.headers || []).some((entry) =>
    entry.source === `/${jsonFile}` &&
    (entry.headers || []).some((header) => header.key === "Cache-Control" && header.value === "public, max-age=0, must-revalidate")
  );
  assert(hasHeader, `vercel.json should set cache validation for /${jsonFile}`);
  const parsed = JSON.parse(readText(jsonFile));
  assert(Number.isInteger(parsed.total) && parsed.total > 0, `${jsonFile} should have a positive total`);
}

assert(html.includes('href="series_library.css"'), "HTML should reference the public stylesheet");
assert(html.includes('src="series_library.js"'), "HTML should reference the public app module");

console.log("Deploy readiness check passed.");
