const { spawn } = require("node:child_process");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const port = Number(process.env.SERVER_CHECK_PORT || 8793);
const baseUrl = `http://127.0.0.1:${port}`;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function startServer() {
  return spawn(process.execPath, ["series_library_server.js"], {
    cwd: root,
    env: { ...process.env, PORT: String(port) },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
}

async function waitForServer() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/`, { method: "HEAD" });
      if (response.status === 200) return;
    } catch {
      // Retry until the local server is ready.
    }
    await wait(100);
  }
  throw new Error(`Local server did not start at ${baseUrl}`);
}

async function expectStatus(pathname, expectedStatus, options = {}) {
  const response = await fetch(`${baseUrl}${pathname}`, options);
  if (response.status !== expectedStatus) {
    throw new Error(`${pathname} returned ${response.status}; expected ${expectedStatus}`);
  }
  return response;
}

(async () => {
  const server = startServer();
  let stderr = "";
  server.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  try {
    await waitForServer();
    const rootHead = await expectStatus("/", 200, { method: "HEAD" });
    if (!rootHead.headers.get("content-type")?.includes("text/html")) {
      throw new Error("Root HEAD response should be HTML.");
    }

    await expectStatus("/series_library.js", 200);
    await expectStatus("/series_library_data_client.js", 200);
    await expectStatus("/series_library_rendering.js", 200);
    const data = await expectStatus("/series_library_data.json", 200);
    if (data.headers.get("cache-control") !== "no-store") {
      throw new Error("Local JSON responses should use no-store cache control.");
    }

    await expectStatus("/series_library.db", 404);
    await expectStatus("/AGENTS.md", 404);
    console.log("Local server smoke check passed.");
  } finally {
    server.kill();
  }

  if (stderr.trim()) {
    process.stderr.write(stderr);
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
