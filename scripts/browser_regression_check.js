const { spawn } = require("node:child_process");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const port = Number(process.env.PORT || 8792);
const url = `http://127.0.0.1:${port}/`;

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function loadPlaywright() {
  try {
    return require("playwright");
  } catch {
    console.log("Browser regression check skipped: install Playwright to run it.");
    console.log("Suggested command: npm install --save-dev playwright");
    return null;
  }
}

async function waitForServer() {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Retry until the local server is ready.
    }
    await wait(100);
  }
  throw new Error(`Local server did not start at ${url}`);
}

function startServer() {
  return spawn(process.execPath, ["series_library_server.js"], {
    cwd: root,
    env: { ...process.env, PORT: String(port) },
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
}

async function runChecks(page) {
  await page.goto(url, { waitUntil: "networkidle" });
  await page.waitForSelector("article.card");

  const initialScroll = await page.evaluate(() => {
    window.scrollTo(0, 520);
    return window.scrollY;
  });
  await page.locator("article.card").first().click();
  await page.waitForSelector("#seriesDetailModal:not([hidden])");
  await page.mouse.wheel(0, 700);
  const modalScrollResult = await page.evaluate((expectedScroll) => ({
    pageScroll: window.scrollY,
    locked: document.body.classList.contains("modal-open"),
    modalOpen: !document.getElementById("seriesDetailModal").hidden,
    expectedScroll,
  }), initialScroll);
  if (!modalScrollResult.locked || !modalScrollResult.modalOpen || modalScrollResult.pageScroll !== modalScrollResult.expectedScroll) {
    throw new Error(`Modal scroll lock regression: ${JSON.stringify(modalScrollResult)}`);
  }
  await page.keyboard.press("Escape");
  await page.waitForSelector("#seriesDetailModal[hidden]");
  const closeScroll = await page.evaluate(() => window.scrollY);
  if (closeScroll !== initialScroll) {
    throw new Error(`Modal close changed page scroll: before=${initialScroll} after=${closeScroll}`);
  }

  await page.locator("#search").fill("witcher");
  await page.waitForFunction(() => document.getElementById("resetFilters").disabled === false);
  const filteredCount = await page.locator("article.card:not(.hidden)").count();
  if (filteredCount < 1) {
    throw new Error("Expected title search to leave at least one visible card.");
  }
  await page.locator("#resetFilters").click();
  await page.waitForFunction(() => document.getElementById("resetFilters").disabled === true);
  const resetState = await page.evaluate(() => ({
    search: document.getElementById("search").value,
    status: document.getElementById("filterStatus").textContent,
    hiddenCards: document.querySelectorAll("article.card.hidden").length,
  }));
  if (resetState.search || resetState.status !== "No filters active" || resetState.hiddenCards !== 0) {
    throw new Error(`Filter reset regression: ${JSON.stringify(resetState)}`);
  }

  await page.locator("article.card").first().click();
  await page.waitForSelector("#seriesDetailModal:not([hidden]) .season-table");
  const detailLoaded = await page.locator("#seriesDetailModal .detail-synopsis").textContent();
  if (!detailLoaded || detailLoaded.includes("No synopsis available")) {
    throw new Error("Detail modal did not load lazy detail payload.");
  }
}

(async () => {
  const playwright = await loadPlaywright();
  if (!playwright) return;

  const server = startServer();
  let stderr = "";
  server.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  let browser;
  try {
    await waitForServer();
    browser = await playwright.chromium.launch();
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await runChecks(page);
    console.log("Browser regression check passed.");
  } finally {
    if (browser) await browser.close();
    server.kill();
  }

  if (stderr.trim()) {
    process.stderr.write(stderr);
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
