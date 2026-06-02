export function escapeText(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");
}

export function imdbTitleUrl(item) {
  return `https://www.imdb.com/title/${encodeURIComponent(item.id)}/`;
}

function lerp(start, end, amount) {
  return start + (end - start) * amount;
}

export function ratingTone(score) {
  const value = Math.max(1, Math.min(10, Number(score) || 1));
  const red = { h: 18, s: 58, l: 28 };
  const yellow = { h: 47, s: 90, l: 58 };
  const green = { h: 134, s: 42, l: 27 };
  const midpoint = 5.5;
  const from = value <= midpoint ? red : yellow;
  const to = value <= midpoint ? yellow : green;
  const t = value <= midpoint ? (value - 1) / (midpoint - 1) : (value - midpoint) / (10 - midpoint);
  const h = lerp(from.h, to.h, t);
  const s = lerp(from.s, to.s, t);
  const l = lerp(from.l, to.l, t);
  const fg = l > 48 ? "oklch(18% 0.018 250)" : "oklch(98% 0.006 250)";
  return `--rating-bg: hsl(${h.toFixed(1)} ${s.toFixed(1)}% ${l.toFixed(1)}%); --rating-fg: ${fg}; --rating-border: hsl(${h.toFixed(1)} ${Math.max(30, s - 14).toFixed(1)}% ${Math.max(20, l - 10).toFixed(1)}%);`;
}

export function trendKind(item) {
  return item.trendKind || null;
}

export function seasonTrendSlope(item) {
  const slope = Number(item.trendSlope);
  return Number.isFinite(slope) ? slope : null;
}

export function renderTrendTag(item) {
  const kind = trendKind(item);
  if (!kind) return "";
  const label = kind === "up" ? "Trend Up" : kind === "down" ? "Trend Down" : "Disaster";
  const slope = seasonTrendSlope(item);
  const title = kind === "disaster"
    ? "Last season is at least 1.5 IMDb points below the first"
    : Number.isFinite(slope) ? `Season rating trend m=${slope.toFixed(2)}` : "Season rating trend";
  return `<span class="trend-tag trend-${kind}" title="${escapeText(title)}">${label}</span>`;
}

export function primaryCategoryList(categories) {
  return categories.filter(category => category !== "Animation");
}

function posterImageAttributes(item, isPriority = false) {
  const loading = isPriority ? "eager" : "lazy";
  const fetchPriority = isPriority ? "high" : "auto";
  return `loading="${loading}" decoding="async" fetchpriority="${fetchPriority}" src="${escapeText(item.poster)}" alt="Poster for ${escapeText(item.title)}"`;
}

export function renderPoster(item, isPriority = false) {
  if (!item.poster) {
    return `<div class="poster"><div class="poster-fallback">No poster</div></div>`;
  }
  return `<div class="poster"><img ${posterImageAttributes(item, isPriority)}></div>`;
}

export function renderCatalogSection(year, items, options = {}) {
  const priorityPosterCount = options.priorityPosterCount || 0;
  const section = document.createElement("section");
  section.className = "year-section";
  section.id = `year-${year}`;
  section.dataset.year = String(year);
  section.innerHTML = `
    <div class="year-heading">
      <h2>${year}</h2>
      <span>${items.length} series</span>
    </div>
    <div class="grid">
      ${items.map((item, index) => `
        <article class="card" tabindex="0" role="button" aria-label="Open details for ${escapeText(item.title)}" data-id="${escapeText(item.id)}" data-categories="${escapeText(item.categories.join(";"))}" data-primary-categories="${escapeText(primaryCategoryList(item.categories).join(";"))}" data-has-animation="${item.categories.includes("Animation") ? "1" : "0"}" data-trend="${escapeText(trendKind(item) || "")}" data-score="${escapeText(Number(item.score).toFixed(1))}" data-rated-seasons="${escapeText(Number(item.ratedSeasonCount || 0))}" data-search="${escapeText(item.title.toLowerCase())}">
          ${renderPoster(item, index < priorityPosterCount)}
          <div class="card-main">
            <div class="card-top">
              <div class="title-row">
                <h3 class="title">${escapeText(item.title)}</h3>
                <div class="rating" title="IMDb rating" style="${ratingTone(item.score)}">IMDb ${escapeText(item.score.toFixed(1))}</div>
              </div>
              <div class="card-meta">
                <div class="facts category-stack">
                  ${item.categories.map(category => `<span class="fact category-chip">${escapeText(category)}</span>`).join("")}
                </div>
                <div class="facts meta-stack">
                  <span class="fact">${escapeText(item.seasonLabel)}</span>
                  <span class="fact">${escapeText(item.years)}</span>
                  <span class="fact">${escapeText(item.primaryOrigin)}</span>
                </div>
              </div>
            </div>
            <div class="card-actions">
              ${renderTrendTag(item)}
              <a class="imdb-link" href="${escapeText(imdbTitleUrl(item))}" target="_blank" rel="noreferrer">IMDb</a>
            </div>
          </div>
        </article>
      `).join("")}
    </div>
  `;
  return section;
}

export function renderDetailPoster(item) {
  if (!item.poster) {
    return `<div class="series-detail-poster"><div class="poster-fallback">No poster</div></div>`;
  }
  return `<div class="series-detail-poster"><img loading="eager" decoding="async" fetchpriority="high" src="${escapeText(item.poster)}" alt="Poster for ${escapeText(item.title)}"></div>`;
}

export function renderSeasonDetails(item) {
  const seasons = item.seasonDetails || [];
  if (!seasons.length) {
    return `
      <section class="season-detail">
        <h3>Seasons</h3>
        <p class="season-empty">No season details available.</p>
      </section>
    `;
  }

  function seasonNumberLabel(season) {
    const value = season.season ?? season.label ?? "";
    const numeric = Number(value);
    if (Number.isFinite(numeric)) return String(numeric);
    return String(value).replace(/^season\s+/i, "") || "-";
  }

  function seasonYearLabel(season) {
    const startYear = Number(season.startYear);
    const endYear = Number(season.endYear);
    if (Number.isFinite(startYear) && Number.isFinite(endYear) && startYear !== endYear) {
      return `${startYear}-${endYear}`;
    }
    if (Number.isFinite(startYear)) return String(startYear);
    if (Number.isFinite(endYear)) return String(endYear);
    return "-";
  }

  function seasonScoreCell(season) {
    if (season.score == null) {
      return `<span class="season-score-empty">Pending</span>`;
    }
    const score = Number(season.score);
    return `<span class="season-score" title="Season IMDb average" style="${ratingTone(score)}">${escapeText(score.toFixed(1))}</span>`;
  }

  return `
    <section class="season-detail">
      <h3>Seasons</h3>
      <div class="season-table">
        <div class="season-row header"><span>Season</span><span>Year</span><span>Episodes</span><span>IMDb avg</span></div>
        ${seasons.map(season => `
          <div class="season-row">
            <span>${escapeText(seasonNumberLabel(season))}</span>
            <span>${escapeText(seasonYearLabel(season))}</span>
            <span>${escapeText(season.episodeCount ?? "-")}</span>
            <span>${seasonScoreCell(season)}</span>
          </div>
        `).join("")}
      </div>
    </section>
  `;
}
