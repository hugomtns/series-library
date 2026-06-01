const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const root = __dirname;
const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || "127.0.0.1";

const publicFiles = new Set([
  "/series_library.html",
  "/series_library.css",
  "/series_library.js",
  "/series_library_data.json",
  "/series_library_data_client.js",
  "/series_library_details.json",
  "/series_library_rendering.js",
]);

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
};

function resolvePublicFile(req) {
  let requested;
  try {
    requested = decodeURIComponent(new URL(req.url, `http://${host}:${port}`).pathname);
  } catch {
    return { status: 400, message: "Bad request" };
  }

  const safePath = requested === "/" ? "/series_library.html" : requested;
  if (!publicFiles.has(safePath)) {
    return { status: 404, message: "Not found" };
  }

  const filePath = path.resolve(root, `.${safePath}`);
  if (!filePath.startsWith(`${root}${path.sep}`)) {
    return { status: 403, message: "Forbidden" };
  }
  return { filePath };
}

function serveStatic(req, res) {
  const resolved = resolvePublicFile(req);
  if (resolved.status) {
    res.writeHead(resolved.status, {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
    });
    res.end(req.method === "HEAD" ? undefined : resolved.message);
    return;
  }

  fs.readFile(resolved.filePath, (error, content) => {
    if (error) {
      res.writeHead(404);
      res.end(req.method === "HEAD" ? undefined : "Not found");
      return;
    }

    const ext = path.extname(resolved.filePath).toLowerCase();
    res.writeHead(200, {
      "content-type": contentTypes[ext] || "application/octet-stream",
      "cache-control": ext === ".json" ? "no-store" : "public, max-age=0, must-revalidate",
      "content-length": content.length,
    });
    res.end(req.method === "HEAD" ? undefined : content);
  });
}

const server = http.createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405);
    res.end("Method not allowed");
    return;
  }
  serveStatic(req, res);
});

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") {
    console.error(`Port ${port} is already in use. The Series Library server may already be running at http://${host}:${port}/series_library.html`);
    console.error(`To use another port, run: $env:PORT=8788; npm run serve`);
    process.exit(1);
  }
  throw error;
});

server.listen(port, host, () => {
  console.log(`Series Library running at http://${host}:${port}/series_library.html`);
});
