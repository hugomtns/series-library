const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const Database = require("better-sqlite3");

const root = path.resolve(__dirname, "..");
const generatedDir = path.join(root, "scripts", ".generated");
const dbPath = path.join(root, "series_library.db");
const dbBackupPath = path.join(generatedDir, "series_library.test-backup.db");
const inputPath = path.join(generatedDir, "null_season_catalog.test.json");
const cachePath = path.join(root, "imdb_sci_fi_catalog_cache", "ttNULLSEASON.json");
const migratePath = path.join(root, "scripts", "migrate_to_sqlite.js");

function removeIfExists(filePath) {
  if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
}

function restoreDb() {
  removeIfExists(`${dbPath}-wal`);
  removeIfExists(`${dbPath}-shm`);
  if (fs.existsSync(dbBackupPath)) {
    fs.copyFileSync(dbBackupPath, dbPath);
    removeIfExists(dbBackupPath);
  }
}

fs.mkdirSync(generatedDir, { recursive: true });
fs.copyFileSync(dbPath, dbBackupPath);

try {
  fs.writeFileSync(inputPath, JSON.stringify({
    generatedAt: "2026-06-05T00:00:00.000Z",
    source: "test",
    series: [{
      year: 2025,
      rank: 1,
      id: "ttNULLSEASON",
      title: "Null Season Fixture",
      score: 7.5,
      votes: 5000,
      years: "2025-",
      type: "tvSeries",
      imdbUrl: "https://www.imdb.com/title/ttNULLSEASON/",
      poster: "",
      synopsis: "Fixture",
      seasons: 1,
      seasonLabel: "1 season",
      episodes: 8,
      genres: ["Comedy"],
      countries: "United States",
      countryCodes: "US",
      primaryOrigin: "US",
      categories: ["Comedy"],
    }],
  }, null, 2));

  fs.writeFileSync(cachePath, JSON.stringify({
    id: "ttNULLSEASON",
    detail: {},
    seasons: [
      null,
      {
        season: "1",
        label: "Season 1",
        episodeCount: 8,
        rating: {
          aggregateRating: 7.5,
          voteCount: 5000,
        },
      },
    ],
    episodes: [],
    refresh: {
      lastRatingCheckAt: "2026-06-05T00:00:00.000Z",
      lastSeasonCheckAt: "2026-06-05T00:00:00.000Z",
      lastDetailCheckAt: "2026-06-05T00:00:00.000Z",
    },
  }, null, 2));

  const result = spawnSync(process.execPath, [migratePath, "--input", inputPath], {
    cwd: root,
    encoding: "utf8",
  });

  if (result.status !== 0) {
    process.stderr.write(result.stdout);
    process.stderr.write(result.stderr);
    throw new Error("Migration should ignore null cached seasons.");
  }

  const db = new Database(dbPath, { readonly: true });
  const row = db.prepare(`
    SELECT COUNT(*) AS count
    FROM series_seasons
    WHERE imdb_id = 'ttNULLSEASON' AND season_number = 1
  `).get();
  db.close();

  if (row.count !== 1) {
    throw new Error(`Expected one migrated season row, found ${row.count}.`);
  }
} finally {
  removeIfExists(inputPath);
  removeIfExists(cachePath);
  restoreDb();
}

console.log("Migration ignores null cached seasons.");
