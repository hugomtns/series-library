const Database = require("better-sqlite3");

const dbPath = process.env.SERIES_LIBRARY_DB;
if (!dbPath) {
  throw new Error("SERIES_LIBRARY_DB is required.");
}

const db = new Database(dbPath, { readonly: true });

try {
  const meta = Object.fromEntries(
    db.prepare("SELECT key, value FROM metadata")
      .all()
      .map((row) => [row.key, row.value])
  );

  const seasonRows = db.prepare(`
    SELECT imdb_id, season_number, label, episode_count, start_year, end_year, imdb_score, vote_count
    FROM series_seasons
    ORDER BY imdb_id ASC, season_number ASC
  `).all();

  const seasonsBySeries = new Map();
  for (const row of seasonRows) {
    if (!seasonsBySeries.has(row.imdb_id)) seasonsBySeries.set(row.imdb_id, []);
    seasonsBySeries.get(row.imdb_id).push({
      season: row.season_number,
      label: row.label,
      episodeCount: row.episode_count,
      startYear: row.start_year,
      endYear: row.end_year,
      score: row.imdb_score,
      votes: row.vote_count,
    });
  }

  const rows = db.prepare(`
    SELECT
      payload_json, imdb_score, vote_count, season_count, season_label, episode_count,
      season_rating_trend_slope, season_rating_trend_intercept, season_rating_trend_points
    FROM series
    ORDER BY start_year ASC, imdb_score DESC, vote_count DESC, title ASC
  `).all();

  const series = rows.map((row) => {
    const item = JSON.parse(row.payload_json);
    item.score = row.imdb_score;
    item.votes = row.vote_count;
    item.seasons = row.season_count;
    item.seasonLabel = row.season_label;
    item.episodes = row.episode_count;
    item.seasonTrend = {
      slope: row.season_rating_trend_slope,
      intercept: row.season_rating_trend_intercept,
      points: row.season_rating_trend_points,
    };
    item.seasonDetails = seasonsBySeries.get(item.id) || [];
    return item;
  });

  const yearCounts = new Map();
  for (const item of series) {
    yearCounts.set(item.year, (yearCounts.get(item.year) || 0) + 1);
  }

  process.stdout.write(JSON.stringify({
    generatedAt: meta.generatedAt || "",
    total: series.length,
    seasonRows: seasonRows.length,
    years: Array.from(yearCounts, ([year, count]) => ({ year, count })),
    series,
  }));
} finally {
  db.close();
}
