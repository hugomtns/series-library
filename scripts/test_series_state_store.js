const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createLocalSeriesStateStore, normalizeSeriesState } = require("../api/series-state-store");

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "series-state-"));
const dbPath = path.join(tmpDir, "series_user_state.db");

try {
  const store = createLocalSeriesStateStore({ dbPath });

  assert.deepStrictEqual(normalizeSeriesState({
    wishlisted: true,
    available: 1,
    seen: "yes",
  }), {
    wishlisted: true,
    available: true,
    seen: false,
  });

  assert.deepStrictEqual(store.getAll(), {});

  const updated = store.set("tt0944947", {
    wishlisted: true,
    available: false,
    seen: true,
  });

  assert.strictEqual(updated.id, "tt0944947");
  assert.strictEqual(updated.wishlisted, true);
  assert.strictEqual(updated.available, false);
  assert.strictEqual(updated.seen, true);
  assert.match(updated.updatedAt, /^\d{4}-\d{2}-\d{2}T/);

  assert.deepStrictEqual(store.getAll().tt0944947, {
    wishlisted: true,
    available: false,
    seen: true,
    updatedAt: updated.updatedAt,
  });

  store.set("tt0944947", {
    wishlisted: false,
    available: false,
    seen: false,
  });

  assert.deepStrictEqual(store.getAll(), {});
  store.close();
  console.log("Series state store test passed.");
} finally {
  fs.rmSync(tmpDir, { recursive: true, force: true });
}
