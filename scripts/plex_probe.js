const fs = require("node:fs");
const path = require("node:path");
const { XMLParser } = require("fast-xml-parser");

const root = path.resolve(__dirname, "..");

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match || process.env[match[1]] !== undefined) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    process.env[match[1]] = value;
  }
}

loadEnvFile(path.join(root, ".env.local"));
loadEnvFile(path.join(root, ".env"));

const plexUrl = String(process.env.PLEX_URL || "http://127.0.0.1:32400").replace(/\/+$/, "");
const plexToken = process.env.PLEX_TOKEN || "";
const requestedSectionKey = process.env.PLEX_SECTION_KEY || "";
const limit = Number(process.env.PLEX_LIMIT || 25);
const trackedSourceGenreNames = new Set(["action", "adventure", "comedy", "fantasy", "sci-fi", "science fiction"]);

if (process.env.PLEX_INSECURE_TLS === "1") {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
}

function requireConfig() {
  const missing = [];
  if (!plexToken) missing.push("PLEX_TOKEN");
  if (missing.length) {
    throw new Error(`Missing ${missing.join(", ")}. Add it to .env or set it in the shell.`);
  }
}

function asArray(value) {
  if (value === undefined || value === null) return [];
  return Array.isArray(value) ? value : [value];
}

function mediaContainer(payload) {
  return payload.MediaContainer || payload.mediaContainer || payload;
}

function extractDirectories(payload) {
  const container = mediaContainer(payload);
  return asArray(container.Directory || container.directory);
}

function extractVideos(payload) {
  const container = mediaContainer(payload);
  return asArray(container.Metadata || container.Video || container.metadata || container.video);
}

function extractGuids(item) {
  const direct = [item.guid, item.Guid, item.GUID].filter(Boolean);
  const nested = asArray(item.Guid || item.GUID || item.guid)
    .map((entry) => (typeof entry === "string" ? entry : entry.id || entry.ID))
    .filter(Boolean);
  return [...new Set([...direct, ...nested])];
}

function extractImdbId(item) {
  for (const guid of extractGuids(item)) {
    const match = String(guid).match(/imdb:\/\/(tt\d+)/i) || String(guid).match(/\b(tt\d{7,})\b/i);
    if (match) return match[1];
  }
  return "";
}

function extractGenres(item) {
  return asArray(item.Genre || item.genre)
    .map((entry) => (typeof entry === "string" ? entry : entry.tag || entry.name || entry.id))
    .filter(Boolean);
}

async function plexGet(pathname, params = {}) {
  const url = new URL(`${plexUrl}${pathname}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") url.searchParams.set(key, String(value));
  }

  const response = await fetch(url, {
    headers: {
      Accept: "application/json, application/xml;q=0.9, text/xml;q=0.8",
      "X-Plex-Token": plexToken,
    },
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Plex ${response.status} ${response.statusText} from ${url.pathname}: ${text.slice(0, 200)}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    return new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "" }).parse(text);
  }
}

function loadCatalogByImdbId() {
  const catalogPath = path.join(root, "series_library_data.json");
  const data = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  return new Map((data.series || []).map((item) => [item.id, item]));
}

function categoryFromSourceDirectory(directoryName) {
  const match = directoryName.match(/^imdb_(.+)_year_files_primary_origin$/);
  if (!match) return directoryName;
  return match[1]
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("-");
}

function sourceYearFromFile(fileName) {
  const match = fileName.match(/_(\d{4})\.csv$/);
  return match ? match[1] : "";
}

function loadSourceRowsByImdbId() {
  const result = new Map();
  const directories = fs
    .readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^imdb_.+_year_files_primary_origin$/.test(entry.name));

  for (const directory of directories) {
    const category = categoryFromSourceDirectory(directory.name);
    const directoryPath = path.join(root, directory.name);
    const files = fs.readdirSync(directoryPath).filter((fileName) => fileName.endsWith(".csv"));
    for (const fileName of files) {
      const content = fs.readFileSync(path.join(directoryPath, fileName), "utf8");
      const imdbIds = new Set(content.match(/\btt\d{7,}\b/g) || []);
      for (const imdbId of imdbIds) {
        if (!result.has(imdbId)) result.set(imdbId, []);
        result.get(imdbId).push({ category, year: sourceYearFromFile(fileName) });
      }
    }
  }

  return result;
}

function analyzeCatalogMisses(rows, sourceRowsByImdbId) {
  return rows
    .filter((row) => row.catalog === "no")
    .map((row) => {
      const sourceRows = sourceRowsByImdbId.get(row.imdbId) || [];
      const sourceCategories = [...new Set(sourceRows.map((sourceRow) => sourceRow.category))];
      const plexGenres = (row.genres || []).map((genre) => String(genre).toLowerCase());
      const hasTrackedPlexGenre = plexGenres.some((genre) => {
        if (trackedSourceGenreNames.has(genre)) return true;
        return genre.includes("sci-fi") || genre.includes("science fiction") || genre.includes("fantasy");
      });
      let reason = "not found in tracked source category CSVs; likely below vote threshold, origin-excluded, or missing from source query";
      if (sourceCategories.length) {
        reason = `found in source categories ${sourceCategories.join(", ")} but absent from exported catalog`;
      } else if (Number(row.year) < 1960) {
        reason = "starts before tracked source range (1960-2026)";
      } else if (plexGenres.length && !hasTrackedPlexGenre) {
        reason = "Plex genres do not include tracked source categories";
      }
      return {
        title: row.title,
        imdbId: row.imdbId,
        reason,
      };
    });
}

function summarizeShow(item, catalogByImdbId) {
  const imdbId = extractImdbId(item);
  const leafCount = Number(item.leafCount || item.leafcount || 0);
  const viewedLeafCount = Number(item.viewedLeafCount || item.viewedleafcount || 0);
  const seen = leafCount > 0 && viewedLeafCount >= leafCount;
  const catalogMatch = imdbId ? catalogByImdbId.get(imdbId) : null;
  return {
    title: item.title || "",
    year: item.year || "",
    imdbId,
    catalog: catalogMatch ? "yes" : "no",
    episodes: leafCount || "",
    watched: viewedLeafCount || "",
    seen: seen ? "yes" : "no",
    genres: extractGenres(item),
  };
}

function printTable(rows) {
  const columns = ["title", "year", "imdbId", "catalog", "episodes", "watched", "seen"];
  const widths = Object.fromEntries(
    columns.map((column) => [
      column,
      Math.min(
        42,
        Math.max(column.length, ...rows.map((row) => String(row[column] ?? "").length)),
      ),
    ]),
  );
  console.log(columns.map((column) => column.padEnd(widths[column])).join("  "));
  console.log(columns.map((column) => "-".repeat(widths[column])).join("  "));
  for (const row of rows) {
    console.log(
      columns
        .map((column) => {
          const value = String(row[column] ?? "");
          return value.length > widths[column] ? `${value.slice(0, widths[column] - 3)}...` : value.padEnd(widths[column]);
        })
        .join("  "),
    );
  }
}

function printCatalogMisses(misses) {
  if (!misses.length) return;
  console.log("");
  console.log("Catalog misses:");
  const rows = misses.map((miss) => ({
    title: miss.title,
    imdbId: miss.imdbId,
    reason: miss.reason,
  }));
  const columns = ["title", "imdbId", "reason"];
  const widths = Object.fromEntries(
    columns.map((column) => [
      column,
      Math.min(64, Math.max(column.length, ...rows.map((row) => String(row[column] ?? "").length))),
    ]),
  );
  console.log(columns.map((column) => column.padEnd(widths[column])).join("  "));
  console.log(columns.map((column) => "-".repeat(widths[column])).join("  "));
  for (const row of rows) {
    console.log(
      columns
        .map((column) => {
          const value = String(row[column] ?? "");
          return value.length > widths[column] ? `${value.slice(0, widths[column] - 3)}...` : value.padEnd(widths[column]);
        })
        .join("  "),
    );
  }
}

function selectTvSection(tvSections) {
  if (!tvSections.length) return null;
  if (!requestedSectionKey) return tvSections[0];
  return tvSections.find((item) => String(item.key) === String(requestedSectionKey)) || null;
}

async function fetchPlexSeriesRows() {
  requireConfig();
  const sectionsPayload = await plexGet("/library/sections");
  const sections = extractDirectories(sectionsPayload);
  const tvSections = sections.filter((section) => section.type === "show");
  const section = selectTvSection(tvSections);
  if (requestedSectionKey && !section) {
    throw new Error(`PLEX_SECTION_KEY=${requestedSectionKey} did not match a TV section.`);
  }
  if (!section) {
    return { tvSections, section: null, rows: [] };
  }

  const catalogByImdbId = loadCatalogByImdbId();
  const showsPayload = await plexGet(`/library/sections/${section.key}/all`, {
    type: 2,
    includeGuids: 1,
    sort: "titleSort",
    ...(limit > 0 ? { limit } : {}),
  });
  const shows = extractVideos(showsPayload);
  return {
    tvSections,
    section,
    rows: shows.map((item) => summarizeShow(item, catalogByImdbId)),
  };
}

async function main() {
  const { tvSections, section, rows } = await fetchPlexSeriesRows();

  console.log(`Plex server: ${plexUrl}`);
  console.log(`TV sections: ${tvSections.length}`);
  for (const section of tvSections) {
    console.log(`- ${section.title || section.key} (key ${section.key})`);
  }

  if (!tvSections.length) return;
  const withImdb = rows.filter((row) => row.imdbId).length;
  const catalogMatches = rows.filter((row) => row.catalog === "yes").length;

  console.log("");
  console.log(`Sample section: ${section.title || section.key} (key ${section.key})`);
  console.log(`Shows returned: ${rows.length}${limit > 0 ? ` (PLEX_LIMIT=${limit})` : ""}`);
  console.log(`IMDb IDs found: ${withImdb}`);
  console.log(`Catalog matches: ${catalogMatches}`);
  if (rows.length) {
    console.log("");
    printTable(rows);
  }
  printCatalogMisses(analyzeCatalogMisses(rows, loadSourceRowsByImdbId()));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  analyzeCatalogMisses,
  fetchPlexSeriesRows,
};
