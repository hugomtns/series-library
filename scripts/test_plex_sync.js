const assert = require("node:assert/strict");
const { buildPlexSyncPlan } = require("./plex_sync");

const currentState = {
  tt_seen: { wishlisted: true, available: false, seen: false },
  tt_unseen: { wishlisted: false, available: false, seen: true },
  tt_same: { wishlisted: false, available: true, seen: false },
  tt_manual: { wishlisted: true, available: true, seen: true },
};
const rows = [
  { imdbId: "tt_seen", catalog: "yes", title: "Seen Show", seen: "yes" },
  { imdbId: "tt_unseen", catalog: "yes", title: "Unseen Show", seen: "no" },
  { imdbId: "tt_same", catalog: "yes", title: "Same Show", seen: "no" },
  { imdbId: "tt_missing", catalog: "no", title: "Missing Show", seen: "yes" },
];

const plan = buildPlexSyncPlan(rows, currentState);

assert.equal(plan.matched, 3);
assert.equal(plan.skipped, 1);
assert.deepEqual(plan.changes, [
  {
    imdbId: "tt_seen",
    title: "Seen Show",
    before: { wishlisted: true, available: false, seen: false },
    after: { wishlisted: true, available: true, seen: true },
  },
  {
    imdbId: "tt_unseen",
    title: "Unseen Show",
    before: { wishlisted: false, available: false, seen: true },
    after: { wishlisted: false, available: true, seen: false },
  },
]);
assert.equal(plan.unchanged.length, 1);
assert.equal(plan.unchanged[0].imdbId, "tt_same");
assert.deepEqual(currentState.tt_manual, { wishlisted: true, available: true, seen: true });

console.log("Plex sync tests passed.");
