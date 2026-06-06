const { createLocalSeriesStateStore } = require("../api/series-state-store");
const { fetchPlexSeriesRows } = require("./plex_probe");

function defaultState() {
  return { wishlisted: false, available: false, seen: false };
}

function comparableState(state) {
  return {
    wishlisted: state?.wishlisted === true,
    available: state?.available === true,
    seen: state?.seen === true,
  };
}

function buildPlexSyncPlan(rows, currentState) {
  const plan = {
    matched: 0,
    skipped: 0,
    changes: [],
    unchanged: [],
  };

  for (const row of rows) {
    if (row.catalog !== "yes" || !row.imdbId) {
      plan.skipped += 1;
      continue;
    }

    plan.matched += 1;
    const before = comparableState(currentState[row.imdbId] || defaultState());
    const after = {
      wishlisted: before.wishlisted,
      available: true,
      seen: row.seen === "yes",
    };
    const entry = { imdbId: row.imdbId, title: row.title, before, after };
    if (before.available === after.available && before.seen === after.seen && before.wishlisted === after.wishlisted) {
      plan.unchanged.push(entry);
    } else {
      plan.changes.push(entry);
    }
  }

  return plan;
}

function printPlan(plan, apply) {
  console.log(`Mode: ${apply ? "apply" : "dry-run"}`);
  console.log(`Matched catalog rows: ${plan.matched}`);
  console.log(`Skipped non-catalog rows: ${plan.skipped}`);
  console.log(`Changes: ${plan.changes.length}`);
  console.log(`Unchanged: ${plan.unchanged.length}`);

  if (!plan.changes.length) return;
  console.log("");
  console.log("Changes:");
  const rows = plan.changes.map((change) => ({
    title: change.title,
    imdbId: change.imdbId,
    available: `${change.before.available ? "yes" : "no"} -> ${change.after.available ? "yes" : "no"}`,
    seen: `${change.before.seen ? "yes" : "no"} -> ${change.after.seen ? "yes" : "no"}`,
    wishlisted: change.after.wishlisted ? "yes" : "no",
  }));
  const columns = ["title", "imdbId", "available", "seen", "wishlisted"];
  const widths = Object.fromEntries(
    columns.map((column) => [
      column,
      Math.min(42, Math.max(column.length, ...rows.map((row) => String(row[column] ?? "").length))),
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

function applyPlan(store, plan) {
  for (const change of plan.changes) {
    store.set(change.imdbId, change.after);
  }
}

async function main() {
  const apply = process.argv.includes("--apply") || process.env.PLEX_SYNC_APPLY === "1";
  const { rows } = await fetchPlexSeriesRows();
  const store = createLocalSeriesStateStore();
  try {
    const plan = buildPlexSyncPlan(rows, store.getAll());
    printPlan(plan, apply);
    if (apply) {
      applyPlan(store, plan);
      console.log("");
      console.log(`Applied ${plan.changes.length} changes.`);
    }
  } finally {
    store.close();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  buildPlexSyncPlan,
};
