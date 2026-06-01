const fs = require("node:fs");
const path = require("node:path");
const Database = require("better-sqlite3");
const { getTrendKind, seasonTrendPoints } = require("./trend_rules");

const root = path.resolve(__dirname, "..");
const dbPath = path.join(root, "series_library.db");
const outPath = path.join(root, "series_library_data.json");
const detailsOutPath = path.join(root, "series_library_details.json");

function getMetadata(db) {
  const rows = db.prepare("SELECT key, value FROM metadata").all();
  return Object.fromEntries(rows.map((row) => [row.key, row.value]));
}

function getSeasonsBySeries(db) {
  const rows = db.prepare(`
    SELECT imdb_id, season_number, episode_count, start_year, end_year, imdb_score
    FROM series_seasons
    ORDER BY imdb_id ASC, season_number ASC
  `).all();

  const bySeries = new Map();
  for (const row of rows) {
    if (!bySeries.has(row.imdb_id)) bySeries.set(row.imdb_id, []);
    bySeries.get(row.imdb_id).push({
      season: row.season_number,
      episodeCount: row.episode_count,
      startYear: row.start_year,
      endYear: row.end_year,
      score: row.imdb_score,
    });
  }
  return bySeries;
}

function getCatalog() {
  const db = new Database(dbPath, { readonly: true });
  try {
    const meta = getMetadata(db);
    const seasonsBySeries = getSeasonsBySeries(db);
    const rows = db.prepare(`
      SELECT
        payload_json, imdb_score, vote_count, season_count, season_label, episode_count,
        season_rating_trend_slope
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
      item.trendSlope = row.season_rating_trend_slope;
      item.seasonDetails = seasonsBySeries.get(item.id) || [];
      item.ratedSeasonCount = seasonTrendPoints(item.seasonDetails).length;
      item.trendKind = getTrendKind(item);
      return item;
    });

    const byYear = new Map();
    for (const item of series) {
      if (!byYear.has(item.year)) byYear.set(item.year, []);
      byYear.get(item.year).push(item);
    }

    const ranked = [];
    for (const [year, items] of byYear) {
      items.sort((a, b) =>
        (Number(b.score) || 0) - (Number(a.score) || 0) ||
        (Number(b.votes) || 0) - (Number(a.votes) || 0) ||
        String(a.title).localeCompare(String(b.title))
      );
      items.forEach((item) => {
        ranked.push(item);
      });
    }

    const details = Object.fromEntries(ranked.map((item) => [
      item.id,
      {
        synopsis: item.synopsis,
        seasonDetails: item.seasonDetails,
      },
    ]));
    const index = ranked.map(({
      synopsis,
      seasonDetails,
      imdbUrl,
      posterWidth,
      posterHeight,
      votes,
      rank,
      type,
      seasons,
      episodes,
      genres,
      countries,
      countryCodes,
      ...item
    }) => item);

    return {
      index: {
        generatedAt: meta.generatedAt || "",
        total: index.length,
        years: Array.from(byYear.entries()).map(([year, items]) => ({ year, count: items.length })),
        series: index,
      },
      details: {
        generatedAt: meta.generatedAt || "",
        total: ranked.length,
        series: details,
      },
    };
  } finally {
    db.close();
  }
}

function omitNullValues(value) {
  if (Array.isArray(value)) return value.map(omitNullValues);
  if (!value || typeof value !== "object") return value;

  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entryValue]) => entryValue !== null && entryValue !== undefined)
      .map(([key, entryValue]) => [key, omitNullValues(entryValue)])
  );
}

const catalog = getCatalog();
fs.writeFileSync(outPath, `${JSON.stringify(omitNullValues(catalog.index))}\n`);
fs.writeFileSync(detailsOutPath, `${JSON.stringify(omitNullValues(catalog.details))}\n`);
console.log(`Exported ${catalog.index.total} series to ${outPath}`);
console.log(`Exported ${catalog.details.total} series details to ${detailsOutPath}`);
