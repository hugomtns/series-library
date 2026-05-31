const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const catalogPath = path.join(root, "imdb_sci_fi_catalog_data.json");
const cacheDir = path.join(root, "imdb_sci_fi_catalog_cache");
const currentYear = new Date().getFullYear();
const batchSize = 5;
const concurrency = Number(process.env.RATING_REFRESH_CONCURRENCY || 2);
const throttleMs = Number(process.env.RATING_REFRESH_THROTTLE_MS || 1500);

function emit(event) {
  process.stdout.write(`${JSON.stringify({ step: "ratings", ...event })}\n`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function fetchJson(uri) {
  for (let attempt = 1; attempt <= 6; attempt++) {
    try {
      const response = await fetch(uri);
      if (!response.ok) {
        throw new Error(`${response.status} ${await response.text()}`);
      }
      const result = await response.json();
      await sleep(throttleMs);
      return result;
    } catch (error) {
      if (attempt === 6) throw error;
      await sleep(Math.min(90000, 10000 * attempt));
    }
  }
}

function cachePathFor(id) {
  return path.join(cacheDir, `${id}.json`);
}

function readCache(id) {
  const filePath = cachePathFor(id);
  if (!fs.existsSync(filePath)) return { id, detail: null, seasons: null };
  return readJson(filePath);
}

function lastRatingCheck(item) {
  const filePath = cachePathFor(item.id);
  if (!fs.existsSync(filePath)) return null;
  const cache = readJson(filePath);
  const value = cache.refresh?.lastRatingCheckAt || fs.statSync(filePath).mtime.toISOString();
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date;
}

function ratingTtlHours(item) {
  const years = String(item.years || "");
  const isOpenEnded = years.endsWith("-");
  if (isOpenEnded || Number(item.year) === currentYear) return 24;
  if (Number(item.year) >= currentYear - 3) return 24 * 7;
  return 24 * 30;
}

function isStale(item, now) {
  const lastChecked = lastRatingCheck(item);
  if (!lastChecked) return true;
  return now - lastChecked > ratingTtlHours(item) * 60 * 60 * 1000;
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

async function run() {
  const catalog = readJson(catalogPath);
  const now = new Date();
  const unique = new Map((catalog.series || []).map((item) => [item.id, item]));
  const staleItems = Array.from(unique.values()).filter((item) => isStale(item, now));
  const batches = chunks(staleItems, batchSize);
  let completed = 0;
  let nextBatch = 0;

  emit({
    current: 0,
    total: staleItems.length,
    status: staleItems.length ? "running" : "complete",
    message: staleItems.length
      ? `Refreshing ${staleItems.length} stale ratings; skipped ${unique.size - staleItems.length} fresh titles`
      : `No stale ratings; skipped ${unique.size} fresh titles`,
  });

  async function worker() {
    while (nextBatch < batches.length) {
      const batch = batches[nextBatch++];
      const query = batch.map((item) => `titleIds=${encodeURIComponent(item.id)}`).join("&");
      const response = await fetchJson(`https://api.imdbapi.dev/titles:batchGet?${query}`);
      const checkedAt = new Date().toISOString();
      for (const detail of response.titles || []) {
        if (!detail.id) continue;
        const cache = readCache(detail.id);
        cache.id = detail.id;
        cache.detail = detail;
        cache.refresh = {
          ...(cache.refresh || {}),
          lastRatingCheckAt: checkedAt,
          lastDetailCheckAt: checkedAt,
        };
        writeJson(cachePathFor(detail.id), cache);
      }
      completed += batch.length;
      emit({
        current: Math.min(completed, staleItems.length),
        total: staleItems.length,
        status: "running",
        message: `Refreshed ${Math.min(completed, staleItems.length)} of ${staleItems.length} stale ratings`,
      });
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, batches.length) }, () => worker()));
  emit({
    current: staleItems.length,
    total: staleItems.length,
    status: "complete",
    message: `Ratings refreshed; skipped ${unique.size - staleItems.length} fresh titles`,
  });
}

run().catch((error) => {
  emit({ current: 0, total: 1, status: "error", message: error.message });
  process.exitCode = 1;
});
