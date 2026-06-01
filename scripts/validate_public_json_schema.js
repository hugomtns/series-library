const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const indexPayload = readJson("series_library_data.json");
const detailPayload = readJson("series_library_details.json");

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.join(root, file), "utf8").replace(/^\uFEFF/, ""));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function assertKeys(name, value, allowedKeys) {
  const keys = Object.keys(value);
  for (const key of keys) {
    assert(allowedKeys.includes(key), `${name} contains unexpected field: ${key}`);
    assert(value[key] !== null && value[key] !== undefined, `${name}.${key} should be omitted instead of null`);
  }
}

function assertOptionalString(name, value) {
  if (value !== undefined) assert(typeof value === "string" && value.length > 0, `${name} should be a non-empty string when present`);
}

function assertOptionalNumber(name, value) {
  if (value !== undefined) assert(typeof value === "number" && Number.isFinite(value), `${name} should be a finite number when present`);
}

function validateIndexPayload(payload) {
  assertKeys("series_library_data", payload, ["generatedAt", "total", "years", "series"]);
  assert(typeof payload.generatedAt === "string" && payload.generatedAt.length > 0, "generatedAt should be a non-empty string");
  assert(Number.isInteger(payload.total) && payload.total > 0, "total should be a positive integer");
  assert(Array.isArray(payload.years), "years should be an array");
  assert(Array.isArray(payload.series), "series should be an array");
  assert(payload.series.length === payload.total, "series length should match total");

  for (const yearInfo of payload.years) {
    assertKeys("year summary", yearInfo, ["year", "count"]);
    assert(Number.isInteger(yearInfo.year), "year summary year should be an integer");
    assert(Number.isInteger(yearInfo.count) && yearInfo.count > 0, "year summary count should be positive");
  }

  for (const item of payload.series) {
    assertKeys("series row", item, [
      "year",
      "id",
      "title",
      "score",
      "years",
      "poster",
      "seasonLabel",
      "primaryOrigin",
      "categories",
      "trendSlope",
      "trendKind",
    ]);
    assert(Number.isInteger(item.year), "series year should be an integer");
    assert(/^tt\d+$/.test(item.id), `series id should be an IMDb title id: ${item.id}`);
    assert(typeof item.title === "string" && item.title.length > 0, "series title should be non-empty");
    assert(typeof item.score === "number" && item.score >= 1 && item.score <= 10, `series score out of range: ${item.id}`);
    assertOptionalString("series.years", item.years);
    assertOptionalString("series.poster", item.poster);
    assertOptionalString("series.seasonLabel", item.seasonLabel);
    assertOptionalString("series.primaryOrigin", item.primaryOrigin);
    assert(Array.isArray(item.categories) && item.categories.length > 0, `series categories missing: ${item.id}`);
    for (const category of item.categories) {
      assert(typeof category === "string" && category.length > 0, `invalid category for ${item.id}`);
    }
    assertOptionalNumber("series.trendSlope", item.trendSlope);
    if (item.trendKind !== undefined) {
      assert(["up", "down", "disaster"].includes(item.trendKind), `invalid trendKind for ${item.id}: ${item.trendKind}`);
    }
  }
}

function validateDetailPayload(payload, expectedTotal) {
  assertKeys("series_library_details", payload, ["generatedAt", "total", "series"]);
  assert(typeof payload.generatedAt === "string" && payload.generatedAt.length > 0, "detail generatedAt should be non-empty");
  assert(payload.total === expectedTotal, "detail total should match index total");
  assert(isPlainObject(payload.series), "detail series should be keyed object");
  assert(Object.keys(payload.series).length === expectedTotal, "detail key count should match total");

  for (const [id, detail] of Object.entries(payload.series)) {
    assert(/^tt\d+$/.test(id), `detail key should be an IMDb title id: ${id}`);
    assertKeys(`detail ${id}`, detail, ["synopsis", "seasonDetails"]);
    assert(typeof detail.synopsis === "string" && detail.synopsis.length > 0, `detail synopsis missing: ${id}`);
    assert(Array.isArray(detail.seasonDetails), `seasonDetails should be an array: ${id}`);
    for (const season of detail.seasonDetails) {
      assertKeys(`season detail ${id}`, season, ["season", "episodeCount", "startYear", "endYear", "score"]);
      assert(Number.isInteger(season.season) && season.season >= 0, `invalid season number: ${id}`);
      if (season.episodeCount !== undefined) assert(Number.isInteger(season.episodeCount) && season.episodeCount >= 0, `invalid episode count: ${id}`);
      if (season.startYear !== undefined) assert(Number.isInteger(season.startYear), `invalid startYear: ${id}`);
      if (season.endYear !== undefined) assert(Number.isInteger(season.endYear), `invalid endYear: ${id}`);
      if (season.score !== undefined) assert(typeof season.score === "number" && season.score >= 0.1 && season.score <= 10, `invalid season score: ${id}`);
    }
  }
}

validateIndexPayload(indexPayload);
validateDetailPayload(detailPayload, indexPayload.total);
console.log("Public JSON schema validation passed.");
