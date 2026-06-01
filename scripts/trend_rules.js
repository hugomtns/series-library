const TREND_RULES = {
  minRatedSeasons: 3,
  minRatedScore: 0.1,
  disasterDrop: -1.5,
  trendUpSlope: 0.3,
  trendDownSlope: -0.3,
};

function finiteSeasonScore(value) {
  const score = Number(value);
  return Number.isFinite(score) && score >= TREND_RULES.minRatedScore ? score : null;
}

function roundOrNull(value, decimals = 4) {
  if (!Number.isFinite(value)) return null;
  return Number(value.toFixed(decimals));
}

function seasonTrendPoints(seasons, { seasonKey = "season", scoreKey = "score" } = {}) {
  return [...(seasons || [])]
    .map((season) => ({
      x: Number(season[seasonKey]),
      y: finiteSeasonScore(season[scoreKey]),
    }))
    .filter((point) => Number.isFinite(point.x) && point.y !== null)
    .sort((a, b) => a.x - b.x);
}

function linearRegression(points) {
  if (points.length < TREND_RULES.minRatedSeasons) return null;

  let sumX = 0;
  let sumY = 0;
  let sumXY = 0;
  let sumXX = 0;
  for (const point of points) {
    sumX += point.x;
    sumY += point.y;
    sumXY += point.x * point.y;
    sumXX += point.x * point.x;
  }

  const n = points.length;
  const denominator = (n * sumXX) - (sumX * sumX);
  if (denominator === 0) return null;

  const slope = ((n * sumXY) - (sumX * sumY)) / denominator;
  const intercept = (sumY - (slope * sumX)) / n;
  return {
    slope: roundOrNull(slope),
    intercept: roundOrNull(intercept),
    points: n,
  };
}

function calculateSeasonRatingTrend(seasons, options = {}) {
  const points = seasonTrendPoints(seasons, options);
  const regression = linearRegression(points);
  return {
    season_rating_trend_slope: regression?.slope ?? null,
    season_rating_trend_intercept: regression?.intercept ?? null,
    season_rating_trend_points: regression?.points ?? points.length,
  };
}

function getTrendKind({ seasonDetails, trendSlope }) {
  const points = seasonTrendPoints(seasonDetails);
  if (points.length < TREND_RULES.minRatedSeasons) return null;

  const firstScore = points[0].y;
  const lastScore = points[points.length - 1].y;
  if (lastScore - firstScore <= TREND_RULES.disasterDrop) return "disaster";

  const slope = Number(trendSlope);
  if (!Number.isFinite(slope)) return null;
  if (slope >= TREND_RULES.trendUpSlope) return "up";
  if (slope <= TREND_RULES.trendDownSlope) return "down";
  return null;
}

module.exports = {
  TREND_RULES,
  calculateSeasonRatingTrend,
  finiteSeasonScore,
  getTrendKind,
  linearRegression,
  seasonTrendPoints,
};
