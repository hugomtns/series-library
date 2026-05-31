const fs = require("node:fs");
const path = require("node:path");
const Database = require("better-sqlite3");

const root = path.resolve(__dirname, "..");
const inputPath = path.join(root, "imdb_sci_fi_catalog_data.json");
const dbPath = path.join(root, "series_library.db");

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
`);

const replaceMeta = db.prepare(`
  INSERT INTO metadata (key, value) VALUES (?, ?)
  ON CONFLICT(key) DO UPDATE SET value = excluded.value
`);
const deleteSeries = db.prepare("DELETE FROM series");
const insertSeries = db.prepare(`
  INSERT INTO series (
    imdb_id, title, type, start_year, end_year, imdb_score, vote_count,
    years_text, imdb_url, poster_url, poster_width, poster_height, synopsis,
    season_count, season_label, episode_count, origin_countries, country_codes,
    primary_origin, payload_json, updated_at
  ) VALUES (
    @imdb_id, @title, @type, @start_year, @end_year, @imdb_score, @vote_count,
    @years_text, @imdb_url, @poster_url, @poster_width, @poster_height,
    @synopsis, @season_count, @season_label, @episode_count, @origin_countries,
    @country_codes, @primary_origin, @payload_json, CURRENT_TIMESTAMP
  )
`);
const insertCategory = db.prepare(`
  INSERT OR IGNORE INTO series_categories (imdb_id, category) VALUES (?, ?)
`);
const insertGenre = db.prepare(`
  INSERT OR IGNORE INTO series_genres (imdb_id, genre) VALUES (?, ?)
`);

const migrate = db.transaction(() => {
  replaceMeta.run("generatedAt", catalog.generatedAt || new Date().toISOString());
  replaceMeta.run("source", catalog.source || "");
  replaceMeta.run("migratedAt", new Date().toISOString());
  deleteSeries.run();

  for (const item of catalog.series || []) {
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
      payload_json: JSON.stringify(item),
    });

    for (const category of item.categories || []) {
      insertCategory.run(item.id, category);
    }
    for (const genre of item.genres || []) {
      insertGenre.run(item.id, genre);
    }
  }
});

migrate();

const count = db.prepare("SELECT COUNT(*) AS count FROM series").get().count;
const yearCount = db.prepare("SELECT COUNT(DISTINCT start_year) AS count FROM series").get().count;
db.close();

console.log(`Migrated ${count} series across ${yearCount} years to ${dbPath}`);
