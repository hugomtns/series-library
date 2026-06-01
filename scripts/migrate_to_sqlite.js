const fs = require("node:fs");
const path = require("node:path");
const Database = require("better-sqlite3");
const { calculateSeasonRatingTrend } = require("./trend_rules");

const root = path.resolve(__dirname, "..");
const inputArgIndex = process.argv.indexOf("--input");
const inputPath = inputArgIndex >= 0 && process.argv[inputArgIndex + 1]
  ? path.resolve(process.argv[inputArgIndex + 1])
  : path.join(root, "scripts", ".generated", "catalog_data.json");
const dbPath = path.join(root, "series_library.db");
const cacheDir = path.join(root, "imdb_sci_fi_catalog_cache");

function readCatalog() {
  if (!fs.existsSync(inputPath)) {
    throw new Error(`Missing catalog JSON: ${inputPath}`);
  }
  return JSON.parse(fs.readFileSync(inputPath, "utf8").replace(/^\uFEFF/, ""));
}

function intOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function readRefreshMetadata(imdbId) {
  const cachePath = path.join(cacheDir, `${imdbId}.json`);
  if (!fs.existsSync(cachePath)) return {};
  try {
    const cache = JSON.parse(fs.readFileSync(cachePath, "utf8").replace(/^\uFEFF/, ""));
    const mtime = fs.statSync(cachePath).mtime.toISOString();
    return {
      last_rating_check_at: cache.refresh?.lastRatingCheckAt || mtime,
      last_season_check_at: cache.refresh?.lastSeasonCheckAt || mtime,
      last_detail_check_at: cache.refresh?.lastDetailCheckAt || mtime,
    };
  } catch {
    return {};
  }
}

function readCachedSeasons(imdbId) {
  const cachePath = path.join(cacheDir, `${imdbId}.json`);
  if (!fs.existsSync(cachePath)) return [];
  try {
    const cache = JSON.parse(fs.readFileSync(cachePath, "utf8").replace(/^\uFEFF/, ""));
    return Array.isArray(cache.seasons) ? cache.seasons : [];
  } catch {
    return [];
  }
}

function readCachedEpisodes(imdbId) {
  const cachePath = path.join(cacheDir, `${imdbId}.json`);
  if (!fs.existsSync(cachePath)) return [];
  try {
    const cache = JSON.parse(fs.readFileSync(cachePath, "utf8").replace(/^\uFEFF/, ""));
    return Array.isArray(cache.episodes) ? cache.episodes : [];
  } catch {
    return [];
  }
}

function average(values) {
  if (!values.length) return null;
  const total = values.reduce((sum, value) => sum + value, 0);
  return Number((total / values.length).toFixed(1));
}

function episodeStatsBySeason(episodes) {
  const statsBySeason = new Map();
  for (const episode of episodes) {
    if (!episode) continue;
    const seasonNumber = intOrNull(episode.season);
    if (seasonNumber === null) continue;

    if (!statsBySeason.has(seasonNumber)) {
      statsBySeason.set(seasonNumber, {
        ratings: [],
        voteCount: 0,
        years: [],
      });
    }

    const stats = statsBySeason.get(seasonNumber);
    const rating = numberOrNull(episode.rating?.aggregateRating);
    if (rating !== null) stats.ratings.push(rating);

    const votes = intOrNull(episode.rating?.voteCount);
    if (votes !== null) stats.voteCount += votes;

    const year = intOrNull(episode.releaseDate?.year);
    if (year !== null) stats.years.push(year);
  }
  return statsBySeason;
}

function minOrNull(values) {
  return values.length ? Math.min(...values) : null;
}

function maxOrNull(values) {
  return values.length ? Math.max(...values) : null;
}

function firstNonNull(...values) {
  return values.find((value) => value !== null && value !== undefined) ?? null;
}

function buildSeasonRows(item) {
  const episodeStats = episodeStatsBySeason(readCachedEpisodes(item.id));
  const seasonRows = [];
  for (const season of readCachedSeasons(item.id)) {
    const seasonNumber = intOrNull(season.season);
    if (seasonNumber === null) continue;
    const stats = episodeStats.get(seasonNumber) || { ratings: [], voteCount: 0, years: [] };
    const seasonScore = firstNonNull(
      average(stats.ratings),
      numberOrNull(season.rating?.aggregateRating ?? season.imdbScore ?? season.score)
    );
    seasonRows.push({
      imdb_id: item.id,
      season_number: seasonNumber,
      label: season.label || `Season ${seasonNumber}`,
      episode_count: intOrNull(season.episodeCount),
      start_year: firstNonNull(intOrNull(season.startYear), minOrNull(stats.years)),
      end_year: firstNonNull(intOrNull(season.endYear), maxOrNull(stats.years)),
      imdb_score: seasonScore,
      vote_count: firstNonNull(intOrNull(season.rating?.voteCount ?? season.votes), stats.ratings.length ? stats.voteCount : null),
      payload_json: JSON.stringify({
        ...season,
        episodeRatingCount: stats.ratings.length,
      }),
    });
  }
  seasonRows.sort((a, b) => a.season_number - b.season_number);
  return seasonRows;
}

function addColumnIfMissing(table, columnDefinition) {
  try {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${columnDefinition}`);
  } catch (error) {
    if (!String(error.message).includes("duplicate column name")) {
      throw error;
    }
  }
}

const catalog = readCatalog();
const db = new Database(dbPath);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

db.exec(`
  CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS series (
    imdb_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    type TEXT,
    start_year INTEGER NOT NULL,
    end_year INTEGER,
    imdb_score REAL,
    vote_count INTEGER,
    years_text TEXT,
    imdb_url TEXT,
    poster_url TEXT,
    poster_width INTEGER,
    poster_height INTEGER,
    synopsis TEXT,
    season_count INTEGER,
    season_label TEXT,
    episode_count INTEGER,
    origin_countries TEXT,
    country_codes TEXT,
    primary_origin TEXT,
    last_rating_check_at TEXT,
    last_season_check_at TEXT,
    last_detail_check_at TEXT,
    season_rating_trend_slope REAL,
    season_rating_trend_intercept REAL,
    season_rating_trend_points INTEGER,
    payload_json TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS series_categories (
    imdb_id TEXT NOT NULL REFERENCES series(imdb_id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    PRIMARY KEY (imdb_id, category)
  );

  CREATE TABLE IF NOT EXISTS series_genres (
    imdb_id TEXT NOT NULL REFERENCES series(imdb_id) ON DELETE CASCADE,
    genre TEXT NOT NULL,
    PRIMARY KEY (imdb_id, genre)
  );

  CREATE TABLE IF NOT EXISTS series_seasons (
    imdb_id TEXT NOT NULL REFERENCES series(imdb_id) ON DELETE CASCADE,
    season_number INTEGER NOT NULL,
    label TEXT,
    episode_count INTEGER,
    start_year INTEGER,
    end_year INTEGER,
    imdb_score REAL,
    vote_count INTEGER,
    payload_json TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (imdb_id, season_number)
  );

  CREATE TABLE IF NOT EXISTS update_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TEXT,
    status TEXT NOT NULL,
    message TEXT
  );

  CREATE TABLE IF NOT EXISTS update_steps (
    run_id INTEGER NOT NULL REFERENCES update_runs(id) ON DELETE CASCADE,
    step_key TEXT NOT NULL,
    label TEXT NOT NULL,
    current INTEGER NOT NULL DEFAULT 0,
    total INTEGER NOT NULL DEFAULT 100,
    status TEXT NOT NULL DEFAULT 'pending',
    message TEXT,
    PRIMARY KEY (run_id, step_key)
  );

  CREATE INDEX IF NOT EXISTS idx_series_start_year ON series(start_year);
  CREATE INDEX IF NOT EXISTS idx_series_score ON series(imdb_score);
  CREATE INDEX IF NOT EXISTS idx_series_primary_origin ON series(primary_origin);
  CREATE INDEX IF NOT EXISTS idx_categories_category ON series_categories(category);
  CREATE INDEX IF NOT EXISTS idx_genres_genre ON series_genres(genre);
  CREATE INDEX IF NOT EXISTS idx_series_seasons_imdb_id ON series_seasons(imdb_id);
`);

addColumnIfMissing("series", "last_rating_check_at TEXT");
addColumnIfMissing("series", "last_season_check_at TEXT");
addColumnIfMissing("series", "last_detail_check_at TEXT");
addColumnIfMissing("series", "season_rating_trend_slope REAL");
addColumnIfMissing("series", "season_rating_trend_intercept REAL");
addColumnIfMissing("series", "season_rating_trend_points INTEGER");
db.exec(`
  CREATE INDEX IF NOT EXISTS idx_series_last_rating_check ON series(last_rating_check_at);
  CREATE INDEX IF NOT EXISTS idx_series_last_season_check ON series(last_season_check_at);
  CREATE INDEX IF NOT EXISTS idx_series_season_rating_trend_slope ON series(season_rating_trend_slope);
`);

const existingRefreshRows = db.prepare(`
  SELECT imdb_id, last_rating_check_at, last_season_check_at, last_detail_check_at
  FROM series
`).all();
const existingRefresh = new Map(existingRefreshRows.map((row) => [row.imdb_id, row]));

const replaceMeta = db.prepare(`
  INSERT INTO metadata (key, value) VALUES (?, ?)
  ON CONFLICT(key) DO UPDATE SET value = excluded.value
`);
const deleteSeries = db.prepare("DELETE FROM series");
const deleteSeasons = db.prepare("DELETE FROM series_seasons");
const insertSeries = db.prepare(`
  INSERT INTO series (
    imdb_id, title, type, start_year, end_year, imdb_score, vote_count,
    years_text, imdb_url, poster_url, poster_width, poster_height, synopsis,
    season_count, season_label, episode_count, origin_countries, country_codes,
    primary_origin, last_rating_check_at, last_season_check_at, last_detail_check_at,
    season_rating_trend_slope, season_rating_trend_intercept, season_rating_trend_points,
    payload_json, updated_at
  ) VALUES (
    @imdb_id, @title, @type, @start_year, @end_year, @imdb_score, @vote_count,
    @years_text, @imdb_url, @poster_url, @poster_width, @poster_height,
    @synopsis, @season_count, @season_label, @episode_count, @origin_countries,
    @country_codes, @primary_origin, @last_rating_check_at, @last_season_check_at,
    @last_detail_check_at, @season_rating_trend_slope, @season_rating_trend_intercept,
    @season_rating_trend_points, @payload_json, CURRENT_TIMESTAMP
  )
`);
const insertCategory = db.prepare(`
  INSERT OR IGNORE INTO series_categories (imdb_id, category) VALUES (?, ?)
`);
const insertGenre = db.prepare(`
  INSERT OR IGNORE INTO series_genres (imdb_id, genre) VALUES (?, ?)
`);
const insertSeason = db.prepare(`
  INSERT INTO series_seasons (
    imdb_id, season_number, label, episode_count, start_year, end_year,
    imdb_score, vote_count, payload_json, updated_at
  ) VALUES (
    @imdb_id, @season_number, @label, @episode_count, @start_year, @end_year,
    @imdb_score, @vote_count, @payload_json, CURRENT_TIMESTAMP
  )
`);

const migrate = db.transaction(() => {
  replaceMeta.run("generatedAt", catalog.generatedAt || new Date().toISOString());
  replaceMeta.run("source", catalog.source || "");
  replaceMeta.run("migratedAt", new Date().toISOString());
  deleteSeasons.run();
  deleteSeries.run();

  for (const item of catalog.series || []) {
    const refresh = readRefreshMetadata(item.id);
    const previousRefresh = existingRefresh.get(item.id) || {};
    const seasonRows = buildSeasonRows(item);
    const trend = calculateSeasonRatingTrend(seasonRows, {
      seasonKey: "season_number",
      scoreKey: "imdb_score",
    });
    insertSeries.run({
      imdb_id: item.id,
      title: item.title || item.id,
      type: item.type || null,
      start_year: intOrNull(item.year),
      end_year: item.years && String(item.years).includes("-")
        ? intOrNull(String(item.years).split("-")[1])
        : null,
      imdb_score: numberOrNull(item.score),
      vote_count: intOrNull(item.votes),
      years_text: item.years || null,
      imdb_url: item.imdbUrl || null,
      poster_url: item.poster || null,
      poster_width: intOrNull(item.posterWidth),
      poster_height: intOrNull(item.posterHeight),
      synopsis: item.synopsis || null,
      season_count: intOrNull(item.seasons),
      season_label: item.seasonLabel || null,
      episode_count: intOrNull(item.episodes),
      origin_countries: item.countries || null,
      country_codes: item.countryCodes || null,
      primary_origin: item.primaryOrigin || null,
      last_rating_check_at: refresh.last_rating_check_at || previousRefresh.last_rating_check_at || null,
      last_season_check_at: refresh.last_season_check_at || previousRefresh.last_season_check_at || null,
      last_detail_check_at: refresh.last_detail_check_at || previousRefresh.last_detail_check_at || null,
      season_rating_trend_slope: trend.season_rating_trend_slope,
      season_rating_trend_intercept: trend.season_rating_trend_intercept,
      season_rating_trend_points: trend.season_rating_trend_points,
      payload_json: JSON.stringify(item),
    });

    for (const category of item.categories || []) {
      insertCategory.run(item.id, category);
    }
    for (const genre of item.genres || []) {
      insertGenre.run(item.id, genre);
    }

    for (const season of seasonRows) {
      insertSeason.run(season);
    }
  }
});

migrate();

const count = db.prepare("SELECT COUNT(*) AS count FROM series").get().count;
const yearCount = db.prepare("SELECT COUNT(DISTINCT start_year) AS count FROM series").get().count;
db.close();

console.log(`Migrated ${count} series across ${yearCount} years to ${dbPath}`);
