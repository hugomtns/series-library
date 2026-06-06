const { createSeriesStateStore } = require("./series-state-store");

const imdbIdPattern = /^tt\d+$/;

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 4096) {
        reject(Object.assign(new Error("Request body is too large."), { statusCode: 413 }));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!body.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(Object.assign(new Error("Request body must be JSON."), { statusCode: 400 }));
      }
    });
    req.on("error", reject);
  });
}

function extractImdbIdFromRequest(req, explicitId) {
  if (explicitId) return explicitId;
  const pathname = new URL(req.url, "http://127.0.0.1").pathname;
  const match = pathname.match(/^\/api\/series-state\/([^/]+)$/);
  return match ? decodeURIComponent(match[1]) : "";
}

async function handleSeriesStateApiRequest(req, res, options = {}) {
  try {
    const store = createSeriesStateStore();
    const imdbId = extractImdbIdFromRequest(req, options.imdbId);

    if (req.method === "GET" && !imdbId) {
      sendJson(res, 200, { series: await store.getAll() });
      return;
    }

    if (req.method === "PUT" && imdbId) {
      if (!imdbIdPattern.test(imdbId)) {
        sendJson(res, 400, { error: "Invalid IMDb title id." });
        return;
      }
      const body = await readJsonBody(req);
      sendJson(res, 200, { series: await store.set(imdbId, body) });
      return;
    }

    sendJson(res, 405, { error: "Method not allowed." });
  } catch (error) {
    sendJson(res, error.statusCode || 500, { error: error.message || "Series state request failed." });
  }
}

module.exports = {
  handleSeriesStateApiRequest,
};
