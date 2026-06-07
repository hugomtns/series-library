const fs = require("node:fs");
const path = require("node:path");
const Database = require("better-sqlite3");

const root = path.resolve(__dirname, "..");
const defaultDbPath = path.join(root, "series_library.db");
const defaultCacheDir = path.join(root, "imdb_sci_fi_catalog_cache");

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function intOrNull(value) {
  const parsed = numberOrNull(value);
  return parsed === null ? null : Math.trunc(parsed);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function cachePathFor(cacheDir, imdbId) {
  return path.join(cacheDir, `${imdbId}.json`);
}

function readCache(cacheDir, imdbId) {
  const filePath = cachePathFor(cacheDir, imdbId);
  if (!fs.existsSync(filePath)) return null;
  return readJson(filePath);
}

function numericSeasons(cache) {
  return (Array.isArray(cache?.seasons) ? cache.seasons : [])
    .filter(Boolean)
    .map((season) => ({
      source: season,
      seasonNumber: intOrNull(season.season),
      episodeCount: intOrNull(season.episodeCount),
    }))
    .filter((season) => season.seasonNumber !== null);
}

function hasUsableRating(value) {
  const rating = numberOrNull(value);
  return rating !== null && rating >= 0.1;
}

function seasonHasRating(season) {
  return hasUsableRating(
    season?.rating?.aggregateRating ??
    season?.imdbScore ??
    season?.score
  );
}

function ratedEpisodeSeasons(cache) {
  const seasons = new Set();
  for (const episode of Array.isArray(cache?.episodes) ? cache.episodes : []) {
    const seasonNumber = intOrNull(episode?.season);
    if (seasonNumber === null) continue;
    if (hasUsableRating(episode?.rating?.aggregateRating)) {
      seasons.add(seasonNumber);
    }
  }
  return seasons;
}

function getSeasonCacheHealth(cache) {
  const seasons = numericSeasons(cache);
  const ratedEpisodeSeasonSet = ratedEpisodeSeasons(cache);
  const returnedEpisodeCount = Array.isArray(cache?.episodes) ? cache.episodes.length : 0;
  const expectedEpisodeCount = seasons.reduce((sum, season) => sum + (season.episodeCount || 0), 0);
  const apiEpisodeTotalCount = intOrNull(cache?.episodeTotalCount);
  const ratedSeasonCount = seasons.filter((season) =>
    seasonHasRating(season.source) || ratedEpisodeSeasonSet.has(season.seasonNumber)
  ).length;
  const numericSeasonCount = seasons.length;
  const strictEpisodeComplete = returnedEpisodeCount > 0 && (
    (apiEpisodeTotalCount !== null && returnedEpisodeCount >= apiEpisodeTotalCount - 1) ||
    (expectedEpisodeCount > 0 && returnedEpisodeCount >= expectedEpisodeCount)
  );
  const usableSeasonComplete = numericSeasonCount > 0 && ratedSeasonCount === numericSeasonCount;
  const hasEpisodeRefresh = Boolean(cache?.refresh?.lastEpisodeRatingCheckAt);

  return {
    numericSeasonCount,
    ratedSeasonCount,
    returnedEpisodeCount,
    expectedEpisodeCount,
    apiEpisodeTotalCount,
    missingEpisodeCount: Math.max(
      0,
      (apiEpisodeTotalCount ?? expectedEpisodeCount) - returnedEpisodeCount
    ),
    strictEpisodeComplete,
    usableSeasonComplete,
    hasEpisodeRefresh,
    isUsable: strictEpisodeComplete || usableSeasonComplete,
    needsRefresh: returnedEpisodeCount === 0 || (
      !hasEpisodeRefresh &&
      !strictEpisodeComplete &&
      !usableSeasonComplete
    ),
  };
}

function readCatalogItems(dbPath = defaultDbPath) {
  const db = new Database(dbPath, { readonly: true });
  try {
    return db.prepare(`
      SELECT payload_json
      FROM series
      ORDER BY start_year ASC, title ASC
    `).all().map((row) => JSON.parse(row.payload_json));
  } finally {
    db.close();
  }
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
    } else {
      args[key] = next;
      index++;
    }
  }
  return args;
}

function filterItems(items, args) {
  const titleId = args["title-id"] || "";
  const category = args.category || "";
  const limit = Number(args.limit || 0);
  const all = Boolean(args.all);
  const skipExisting = Boolean(args["skip-existing"]);

  let selected = titleId
    ? items.filter((item) => item.id === titleId)
    : category
      ? items.filter((item) => Array.isArray(item.categories) && item.categories.includes(category))
      : all
        ? items
        : skipExisting
          ? items
          : items.filter((item) => String(item.years || "").endsWith("-"));

  if (limit > 0) selected = selected.slice(0, limit);
  return selected;
}

function buildHealthRows(items, cacheDir = defaultCacheDir) {
  return items.map((item) => {
    const cache = readCache(cacheDir, item.id);
    const health = getSeasonCacheHealth(cache);
    return {
      id: item.id,
      title: item.title,
      years: item.years,
      categories: item.categories || [],
      ...health,
    };
  });
}

function selectRefreshItems(items, cacheDir = defaultCacheDir, skipExisting = false, cacheReader = null) {
  if (!skipExisting) return items;
  return items.filter((item) => {
    const cache = cacheReader ? cacheReader(item.id) : readCache(cacheDir, item.id);
    return getSeasonCacheHealth(cache).needsRefresh;
  });
}

function runCli() {
  const args = parseArgs(process.argv.slice(2));
  const dbPath = args.db || defaultDbPath;
  const cacheDir = args["cache-dir"] || defaultCacheDir;
  const items = filterItems(readCatalogItems(dbPath), args);

  if (args["select-refresh"]) {
    const selected = selectRefreshItems(items, cacheDir, Boolean(args["skip-existing"]));
    process.stdout.write(JSON.stringify(selected));
    return;
  }

  const rows = buildHealthRows(items, cacheDir);
  const strictIncomplete = rows.filter((row) => !row.strictEpisodeComplete);
  const strictIncompleteButUsable = strictIncomplete.filter((row) => row.usableSeasonComplete);
  const partialSeasonCoverage = strictIncomplete.filter((row) => !row.usableSeasonComplete);
  const refreshCandidates = rows.filter((row) => row.needsRefresh);
  const summary = {
    total: rows.length,
    strictIncomplete: strictIncomplete.length,
    strictIncompleteButUsable: strictIncompleteButUsable.length,
    usableIncomplete: partialSeasonCoverage.length,
    usableComplete: rows.length - partialSeasonCoverage.length,
    refreshCandidates: refreshCandidates.length,
    strictIncompleteButUsableTitles: strictIncompleteButUsable
      .sort((a, b) => b.missingEpisodeCount - a.missingEpisodeCount)
      .map((row) => ({
        id: row.id,
        title: row.title,
        years: row.years,
        ratedSeasonCount: row.ratedSeasonCount,
        numericSeasonCount: row.numericSeasonCount,
        returnedEpisodeCount: row.returnedEpisodeCount,
        expectedEpisodeCount: row.apiEpisodeTotalCount ?? row.expectedEpisodeCount,
        missingEpisodeCount: row.missingEpisodeCount,
      })),
    partialSeasonCoverage: partialSeasonCoverage
      .sort((a, b) => b.missingEpisodeCount - a.missingEpisodeCount)
      .map((row) => ({
        id: row.id,
        title: row.title,
        years: row.years,
        ratedSeasonCount: row.ratedSeasonCount,
        numericSeasonCount: row.numericSeasonCount,
        returnedEpisodeCount: row.returnedEpisodeCount,
        expectedEpisodeCount: row.apiEpisodeTotalCount ?? row.expectedEpisodeCount,
        missingEpisodeCount: row.missingEpisodeCount,
      })),
  };
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

if (require.main === module) {
  runCli();
}

module.exports = {
  getSeasonCacheHealth,
  selectRefreshItems,
  buildHealthRows,
};
