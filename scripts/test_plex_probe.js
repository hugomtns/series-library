const assert = require("node:assert/strict");
const { analyzeCatalogMisses } = require("./plex_probe");

const rows = [
  { title: "In Catalog", imdbId: "tt0000001", catalog: "yes" },
  { title: "Source Hit", imdbId: "tt0000002", catalog: "no" },
  { title: "Old Source Miss", imdbId: "tt0000003", catalog: "no", year: 1959, genres: ["Science Fiction"] },
  { title: "Genre Miss", imdbId: "tt0000004", catalog: "no", year: 2008, genres: ["Drama", "Crime"] },
  { title: "Tracked Genre Miss", imdbId: "tt0000005", catalog: "no", year: 2015, genres: ["Comedy"] },
];
const sourceRowsByImdbId = new Map([
  ["tt0000002", [{ category: "Sci-Fi", year: "2020" }, { category: "Action", year: "2020" }]],
]);

const misses = analyzeCatalogMisses(rows, sourceRowsByImdbId);

assert.deepEqual(misses, [
  {
    title: "Source Hit",
    imdbId: "tt0000002",
    reason: "found in source categories Sci-Fi, Action but absent from exported catalog",
  },
  {
    title: "Old Source Miss",
    imdbId: "tt0000003",
    reason: "starts before tracked source range (1960-2026)",
  },
  {
    title: "Genre Miss",
    imdbId: "tt0000004",
    reason: "Plex genres do not include tracked source categories",
  },
  {
    title: "Tracked Genre Miss",
    imdbId: "tt0000005",
    reason: "not found in tracked source category CSVs; likely below vote threshold, origin-excluded, or missing from source query",
  },
]);

console.log("Plex probe tests passed.");
