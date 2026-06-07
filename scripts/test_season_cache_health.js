const { getSeasonCacheHealth, selectRefreshItems } = require("./season_cache_health");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const allSeasonsRatedButEpisodeTotalsDisagree = {
  seasons: [
    { season: "1", episodeCount: 10 },
    { season: "2", episodeCount: 10 },
  ],
  episodes: [
    { season: "1", rating: { aggregateRating: 7.1 } },
    { season: "2", rating: { aggregateRating: 7.4 } },
  ],
  episodeTotalCount: 20,
  refresh: { lastEpisodeRatingCheckAt: "2026-06-07T00:00:00.000Z" },
};

const partialSeasonCoverage = {
  seasons: [
    { season: "1", episodeCount: 10 },
    { season: "2", episodeCount: 10 },
  ],
  episodes: [
    { season: "1", rating: { aggregateRating: 7.1 } },
  ],
  episodeTotalCount: 20,
};

const previouslyRefreshedPartialSeasonCoverage = {
  ...partialSeasonCoverage,
  refresh: { lastEpisodeRatingCheckAt: "2026-06-07T00:00:00.000Z" },
};

const usableHealth = getSeasonCacheHealth(allSeasonsRatedButEpisodeTotalsDisagree);
assert(!usableHealth.strictEpisodeComplete, "Fixture should not be strict episode complete.");
assert(usableHealth.usableSeasonComplete, "All rated seasons should make the cache usable.");
assert(!usableHealth.needsRefresh, "Usable season coverage should not be refreshed by -SkipExisting.");

const partialHealth = getSeasonCacheHealth(partialSeasonCoverage);
assert(!partialHealth.usableSeasonComplete, "Partial season coverage should be reported.");
assert(partialHealth.needsRefresh, "Never-refreshed partial season coverage should be refreshable.");

const refreshedPartialHealth = getSeasonCacheHealth(previouslyRefreshedPartialSeasonCoverage);
assert(!refreshedPartialHealth.usableSeasonComplete, "Previously refreshed partial coverage should still be reported.");
assert(!refreshedPartialHealth.needsRefresh, "Successful partial API responses should not be retried forever.");

const items = [{ id: "usable" }, { id: "partial" }];
const caches = new Map([
  ["usable", allSeasonsRatedButEpisodeTotalsDisagree],
  ["partial", previouslyRefreshedPartialSeasonCoverage],
]);
const selected = selectRefreshItems(items, "", true, (id) => caches.get(id));
assert(selected.length === 0, "Previously refreshed partial caches should not be selected by default.");

console.log("Season cache health distinguishes usable partial episode caches.");
