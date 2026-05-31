const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const { spawn } = require("node:child_process");
const Database = require("better-sqlite3");

const root = __dirname;
const dbPath = path.join(root, "series_library.db");
const port = Number(process.env.PORT || 8787);

let clients = new Set();
let activeUpdate = null;
let lastUpdate = null;

function openDb() {
  if (!fs.existsSync(dbPath)) {
    throw new Error("series_library.db is missing. Run npm run migrate first.");
  }
  return new Database(dbPath, { readonly: true });
}

function getMetadata(db) {
  const rows = db.prepare("SELECT key, value FROM metadata").all();
  return Object.fromEntries(rows.map((row) => [row.key, row.value]));
}

function getCatalog() {
  const db = openDb();
  try {
    const meta = getMetadata(db);
    const rows = db.prepare(`
      SELECT payload_json, imdb_score, vote_count, season_count, season_label, episode_count
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
      items.forEach((item, index) => {
        item.rank = index + 1;
        ranked.push(item);
      });
    }

    return {
      generatedAt: meta.generatedAt || "",
      source: meta.source || "",
      total: ranked.length,
      years: Array.from(byYear.entries()).map(([year, items]) => ({ year, count: items.length })),
      series: ranked,
    };
  } finally {
    db.close();
  }
}

function itemMap(catalog) {
  return new Map((catalog.series || []).map((item) => [item.id, item]));
}

function tagText(item) {
  return (item.categories || []).join(", ");
}

function scoreValue(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Number(parsed.toFixed(1)) : null;
}

function buildUpdateLog(beforeCatalog, afterCatalog) {
  const before = itemMap(beforeCatalog);
  const after = itemMap(afterCatalog);
  const newSeries = [];
  const seasonUpdates = [];
  const ratingUpdates = [];
  const dataUpdates = [];

  for (const item of after.values()) {
    const previous = before.get(item.id);
    if (!previous) {
      newSeries.push({
        id: item.id,
        title: item.title,
        year: item.year,
        tags: item.categories || [],
        score: item.score,
        seasons: item.seasons,
        imdbUrl: item.imdbUrl,
      });
      continue;
    }

    if (Number(previous.seasons) !== Number(item.seasons) || Number(previous.episodes) !== Number(item.episodes)) {
      seasonUpdates.push({
        id: item.id,
        title: item.title,
        year: item.year,
        tags: item.categories || [],
        seasonsBefore: previous.seasons,
        seasonsAfter: item.seasons,
        episodesBefore: previous.episodes,
        episodesAfter: item.episodes,
        imdbUrl: item.imdbUrl,
      });
    }

    const previousScore = scoreValue(previous.score);
    const nextScore = scoreValue(item.score);
    if (previousScore !== nextScore) {
      ratingUpdates.push({
        id: item.id,
        title: item.title,
        year: item.year,
        tags: item.categories || [],
        ratingBefore: previousScore,
        ratingAfter: nextScore,
        votesBefore: previous.votes,
        votesAfter: item.votes,
        imdbUrl: item.imdbUrl,
      });
    } else if (
      String(previous.title || "") !== String(item.title || "") ||
      String(previous.years || "") !== String(item.years || "") ||
      String(previous.synopsis || "") !== String(item.synopsis || "") ||
      String(previous.poster || "") !== String(item.poster || "")
    ) {
      dataUpdates.push({
        id: item.id,
        title: item.title,
        year: item.year,
        tags: item.categories || [],
        changed: [
          String(previous.title || "") !== String(item.title || "") ? "title" : null,
          String(previous.years || "") !== String(item.years || "") ? "years" : null,
          String(previous.synopsis || "") !== String(item.synopsis || "") ? "synopsis" : null,
          String(previous.poster || "") !== String(item.poster || "") ? "poster" : null,
        ].filter(Boolean),
        imdbUrl: item.imdbUrl,
      });
    }
  }

  newSeries.sort((a, b) => a.year - b.year || a.title.localeCompare(b.title));
  seasonUpdates.sort((a, b) => a.year - b.year || a.title.localeCompare(b.title));
  ratingUpdates.sort((a, b) => Math.abs((b.ratingAfter || 0) - (b.ratingBefore || 0)) - Math.abs((a.ratingAfter || 0) - (a.ratingBefore || 0)));
  dataUpdates.sort((a, b) => a.year - b.year || a.title.localeCompare(b.title));

  return {
    generatedAt: new Date().toISOString(),
    totals: {
      before: beforeCatalog.total || 0,
      after: afterCatalog.total || 0,
      newSeries: newSeries.length,
      seasonUpdates: seasonUpdates.length,
      ratingUpdates: ratingUpdates.length,
      dataUpdates: dataUpdates.length,
    },
    newSeries,
    seasonUpdates,
    ratingUpdates,
    dataUpdates,
  };
}

function sendJson(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
  });
  res.end(body);
}

function sendEvent(event) {
  const payload = `data: ${JSON.stringify(event)}\n\n`;
  for (const client of clients) {
    client.write(payload);
  }
}

function startUpdate() {
  if (activeUpdate) return activeUpdate;

  const beforeCatalog = getCatalog();

  const run = {
    id: Date.now(),
    status: "running",
    steps: {
      newSeries: { label: "New series", current: 0, total: 3, status: "running" },
      seasons: { label: "Seasons", current: 0, total: 1, status: "pending" },
      ratings: { label: "Ratings", current: 0, total: 1, status: "pending" },
      rebuild: { label: "Rebuild database", current: 0, total: 1, status: "pending" },
    },
  };
  activeUpdate = run;
  sendEvent({ type: "update", run });

  const commands = [
    {
      key: "newSeries",
      label: "Refresh current-year genre searches",
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/update_current_year_sources.ps1"],
    },
    {
      key: "seasons",
      label: "Refresh open-ended series seasons",
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/refresh_open_series_seasons.ps1"],
    },
    {
      key: "ratings",
      label: "Refresh existing ratings",
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/refresh_existing_ratings.ps1"],
    },
    {
      key: "rebuild",
      label: "Rebuild catalog and SQLite database",
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/rebuild_catalog_and_db.ps1"],
    },
  ];

  (async () => {
    try {
      for (const task of commands) {
        for (const step of Object.values(run.steps)) {
          if (step.status === "running") step.status = "complete";
        }
        run.steps[task.key].status = "running";
        run.steps[task.key].message = task.label;
        sendEvent({ type: "update", run });
        await runCommand(task.command, task.args, task.key, run);
        run.steps[task.key].current = run.steps[task.key].total;
        run.steps[task.key].status = "complete";
        sendEvent({ type: "update", run });
      }
      const afterCatalog = getCatalog();
      run.log = buildUpdateLog(beforeCatalog, afterCatalog);
      run.status = "complete";
      sendEvent({ type: "update", run });
    } catch (error) {
      run.status = "error";
      run.error = error.message;
      sendEvent({ type: "update", run });
    } finally {
      lastUpdate = run;
      activeUpdate = null;
    }
  })();

  return run;
}

function runCommand(command, args, stepKey, run) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, shell: false });
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      const lines = text.split(/\r?\n/).filter(Boolean);
      for (const line of lines) {
        try {
          const event = JSON.parse(line);
          if (event.step && run.steps[event.step]) {
            Object.assign(run.steps[event.step], event);
          } else if (event.current != null) {
            Object.assign(run.steps[stepKey], event);
          }
        } catch {
          run.steps[stepKey].message = line;
        }
        sendEvent({ type: "update", run });
      }
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `${command} exited with code ${code}`));
      }
    });
  });
}

function serveStatic(req, res) {
  const requested = decodeURIComponent(new URL(req.url, `http://localhost:${port}`).pathname);
  const safePath = requested === "/" ? "/series_library.html" : requested;
  const filePath = path.normalize(path.join(root, safePath));
  if (!filePath.startsWith(root)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  fs.readFile(filePath, (error, content) => {
    if (error) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const types = {
      ".html": "text/html; charset=utf-8",
      ".json": "application/json; charset=utf-8",
      ".css": "text/css; charset=utf-8",
      ".js": "text/javascript; charset=utf-8",
    };
    res.writeHead(200, { "content-type": types[ext] || "application/octet-stream" });
    res.end(content);
  });
}

const server = http.createServer((req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${port}`);
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET,POST,OPTIONS",
        "access-control-allow-headers": "content-type",
      });
      res.end();
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/series") {
      sendJson(res, 200, getCatalog());
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/status") {
      const db = openDb();
      const meta = getMetadata(db);
      const count = db.prepare("SELECT COUNT(*) AS count FROM series").get().count;
      db.close();
      sendJson(res, 200, { count, activeUpdate, lastUpdate, metadata: meta });
      return;
    }
    if (req.method === "POST" && url.pathname === "/api/update/start") {
      sendJson(res, 202, startUpdate());
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/update/events") {
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive",
        "access-control-allow-origin": "*",
      });
      res.write("\n");
      clients.add(res);
      if (activeUpdate) sendEvent({ type: "update", run: activeUpdate });
      req.on("close", () => clients.delete(res));
      return;
    }
    serveStatic(req, res);
  } catch (error) {
    sendJson(res, 500, { error: error.message });
  }
});

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") {
    console.error(`Port ${port} is already in use. The Series Library server may already be running at http://127.0.0.1:${port}/series_library.html`);
    console.error(`To use another port, run: $env:PORT=8788; npm run serve`);
    process.exit(1);
  }
  throw error;
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Series Library running at http://127.0.0.1:${port}/series_library.html`);
});
