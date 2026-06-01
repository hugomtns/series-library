const fs = require("fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function posterHost(url) {
  try {
    return new URL(url).host;
  } catch {
    return "invalid";
  }
}

function amazonVariant(url) {
  const match = String(url).match(/@\.([^/]+)\.(jpg|jpeg|png|webp)$/i);
  return match ? match[1] : "unknown";
}

const catalog = readJson("series_library_data.json");
const posters = catalog.series
  .map(item => item.poster)
  .filter(Boolean);
const hostCounts = new Map();
const variantCounts = new Map();

for (const poster of posters) {
  const host = posterHost(poster);
  const variant = amazonVariant(poster);
  hostCounts.set(host, (hostCounts.get(host) || 0) + 1);
  variantCounts.set(variant, (variantCounts.get(variant) || 0) + 1);
}

const uniquePosters = new Set(posters);
const amazonPosters = posters.filter(url => posterHost(url).endsWith("media-amazon.com"));
const defaultAmazonVariantCount = posters.filter(url => amazonVariant(url) === "_V1_").length;

const report = {
  totalSeries: catalog.total,
  posterUrls: posters.length,
  uniquePosterUrls: uniquePosters.size,
  missingPosters: catalog.total - posters.length,
  amazonPosterUrls: amazonPosters.length,
  defaultAmazonVariantUrls: defaultAmazonVariantCount,
  hosts: Object.fromEntries([...hostCounts.entries()].sort((a, b) => b[1] - a[1])),
  variants: Object.fromEntries([...variantCounts.entries()].sort((a, b) => b[1] - a[1])),
  currentDeliveryControls: [
    "Initial viewport posters are eager/high priority.",
    "Remaining catalog posters are lazy/auto priority.",
    "Detail modal poster is eager/high priority after user intent.",
  ],
  nextStepIfBandwidthIsHigh: "Measure transferred poster bytes in production before adding generated thumbnails or a proxy.",
};

console.log(JSON.stringify(report, null, 2));
