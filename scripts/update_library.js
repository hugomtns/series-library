const { spawn } = require("node:child_process");
const path = require("node:path");

const root = path.resolve(__dirname, "..");

const tasks = [
  {
    key: "nearMisses",
    label: "Build under-5k near-miss report",
    command: "powershell.exe",
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/preview_under_5k_near_misses.ps1", "-NonBlocking"],
  },
  {
    key: "newSeries",
    label: "Refresh current-year genre searches",
    command: "powershell.exe",
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/update_current_year_sources.ps1"],
  },
  {
    key: "seasons",
    label: "Refresh seasons and episode ratings",
    command: "powershell.exe",
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/refresh_open_series_seasons.ps1", "-SkipExisting"],
  },
  {
    key: "ratings",
    label: "Refresh existing ratings",
    command: "node",
    args: ["scripts/refresh_existing_ratings.js"],
  },
  {
    key: "rebuild",
    label: "Rebuild SQLite and public JSON",
    command: "powershell.exe",
    args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/rebuild_catalog_and_db.ps1"],
  },
];

function writeProgress(taskIndex, task, event = {}) {
  const current = event.current ?? 0;
  const total = event.total ?? 1;
  const message = event.message || task.label;
  const prefix = `[${taskIndex + 1}/${tasks.length}] ${task.key}`;
  console.log(`${prefix} ${current}/${total} ${message}`);
}

function runTask(task, index) {
  return new Promise((resolve, reject) => {
    writeProgress(index, task, { current: 0, total: 1 });
    const child = spawn(task.command, task.args, { cwd: root, shell: false });
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      const lines = chunk.toString().split(/\r?\n/).filter(Boolean);
      for (const line of lines) {
        try {
          const event = JSON.parse(line);
          writeProgress(index, task, event);
        } catch {
          console.log(line);
        }
      }
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr += text;
      process.stderr.write(text);
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        writeProgress(index, task, { current: 1, total: 1, message: "complete" });
        resolve();
      } else {
        reject(new Error(stderr.trim() || `${task.command} exited with code ${code}`));
      }
    });
  });
}

(async () => {
  for (const [index, task] of tasks.entries()) {
    await runTask(task, index);
  }
  console.log("Library update complete.");
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
