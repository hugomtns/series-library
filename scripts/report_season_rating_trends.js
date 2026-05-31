const path = require("node:path");
const Database = require("better-sqlite3");

const dbPath = path.resolve(__dirname, "..", "series_library.db");
const db = new Database(dbPath, { readonly: true });

const rows = db.prepare(`
  SELECT title, start_year, season_count, season_rating_trend_points, season_rating_trend_slope
  FROM series
  WHERE season_count >= 3
  ORDER BY season_rating_trend_slope DESC NULLS LAST, title ASC
`).all();

db.close();

for (const row of rows) {
  const slope = row.season_rating_trend_slope === null
    ? "pending"
    : Number(row.season_rating_trend_slope).toFixed(4);
  console.log([
    row.title,
    row.start_year,
    `${row.season_count} seasons`,
    `${row.season_rating_trend_points || 0} rated`,
    `m=${slope}`,
  ].join("\t"));
}
