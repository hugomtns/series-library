async function loadCatalogData() {
  const response = await fetch("series_library_data.json", { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Catalog request failed: ${response.status}`);
  }
  return response.json();
}

async function loadSeriesDetails() {
  const response = await fetch("series_library_details.json", { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Series detail request failed: ${response.status}`);
  }
  return response.json();
}

let data = await loadCatalogData();
let detailsById = null;
let detailsPromise = null;
let byYear = new Map();
let seriesById = new Map();
function rebuildYearMap() {
  byYear = new Map();
  seriesById = new Map();
  for (const item of data.series) {
    if (!byYear.has(item.year)) byYear.set(item.year, []);
    byYear.get(item.year).push(item);
    seriesById.set(item.id, item);
  }
}
rebuildYearMap();

const yearNav = document.getElementById("yearNav");
const yearSelect = document.getElementById("yearSelect");
const categoryFilter = document.getElementById("categoryFilter");
const categoryTrigger = document.getElementById("categoryTrigger");
const categoryAll = document.getElementById("categoryAll");
const categoryChoices = Array.from(document.querySelectorAll(".category-choice"));
const filterPanel = document.getElementById("filterPanel");
const trendFilter = document.getElementById("trendFilter");
const trendTrigger = document.getElementById("trendTrigger");
const trendAll = document.getElementById("trendAll");
const trendChoices = Array.from(document.querySelectorAll(".trend-choice"));
const minScoreInput = document.getElementById("minScore");
const maxScoreInput = document.getElementById("maxScore");
const seriesDetailModal = document.getElementById("seriesDetailModal");
const seriesDetailBody = document.getElementById("seriesDetailBody");
const catalog = document.getElementById("catalog");
const totalCount = document.getElementById("totalCount");
const yearCount = document.getElementById("yearCount");
const metaLine = document.getElementById("metaLine");
const search = document.getElementById("search");
const empty = document.getElementById("empty");

let selectedCategories = new Set(categoryChoices.map(input => input.value));
let selectedTrends = new Set(trendChoices.map(input => input.value));
let lastSeriesTrigger = null;
let lockedScrollY = 0;
const focusableSelectors = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])"
].join(",");
const mobileFilterQuery = window.matchMedia("(max-width: 620px)");

function syncFilterPanelForViewport(event = mobileFilterQuery) {
  filterPanel.open = !event.matches;
}

syncFilterPanelForViewport();
mobileFilterQuery.addEventListener("change", syncFilterPanelForViewport);

totalCount.textContent = data.total.toLocaleString();
yearCount.textContent = data.years.length.toLocaleString();
metaLine.textContent = `Generated ${data.generatedAt}`;

const formatter = new Intl.NumberFormat();

function allCategoriesSelected() {
  return selectedCategories.size === categoryChoices.length;
}

function allTrendsSelected() {
  return selectedTrends.size === trendChoices.length;
}

function updateCategoryTrigger() {
  if (allCategoriesSelected()) {
    categoryTrigger.textContent = "All categories";
    categoryAll.checked = true;
  } else if (selectedCategories.size === 0) {
    categoryTrigger.textContent = "No categories";
    categoryAll.checked = false;
  } else {
    categoryTrigger.textContent = Array.from(selectedCategories).join(", ");
    categoryAll.checked = false;
  }

  for (const input of categoryChoices) {
    input.checked = selectedCategories.has(input.value);
  }
}

function updateTrendTrigger() {
  const labels = { up: "Trend Up", down: "Trend Down", disaster: "Disaster" };
  if (allTrendsSelected()) {
    trendTrigger.textContent = "All trends";
    trendAll.checked = true;
  } else if (selectedTrends.size === 0) {
    trendTrigger.textContent = "No trends";
    trendAll.checked = false;
  } else {
    trendTrigger.textContent = Array.from(selectedTrends).map(value => labels[value]).join(", ");
    trendAll.checked = false;
  }

  for (const input of trendChoices) {
    input.checked = selectedTrends.has(input.value);
  }
}

function escapeText(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");
}

function renderPoster(item) {
  if (!item.poster) {
    return `<div class="poster"><div class="poster-fallback">No poster</div></div>`;
  }
  return `<div class="poster"><img loading="lazy" src="${escapeText(item.poster)}" alt="Poster for ${escapeText(item.title)}"></div>`;
}

function imdbTitleUrl(item) {
  return `https://www.imdb.com/title/${encodeURIComponent(item.id)}/`;
}

function lerp(start, end, amount) {
  return start + (end - start) * amount;
}

function ratingTone(score) {
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

function trendKind(item) {
  return item.trendKind || null;
}

function seasonTrendSlope(item) {
  const slope = Number(item.trendSlope);
  return Number.isFinite(slope) ? slope : null;
}

function renderTrendTag(item) {
  const kind = trendKind(item);
  if (!kind) return "";
  const label = kind === "up" ? "Trend Up" : kind === "down" ? "Trend Down" : "Disaster";
  const slope = seasonTrendSlope(item);
  const title = kind === "disaster"
    ? "Last season is at least 1.5 IMDb points below the first"
    : Number.isFinite(slope) ? `Season rating trend m=${slope.toFixed(2)}` : "Season rating trend";
  return `<span class="trend-tag trend-${kind}" title="${escapeText(title)}">${label}</span>`;
}

function itemMatchesCategory(item) {
  if (item.categories.includes("Animation") && !selectedCategories.has("Animation")) {
    return false;
  }

  const primaryCategories = item.categories.filter(category => category !== "Animation");
  return primaryCategories.some(category => selectedCategories.has(category));
}

function itemMatchesTrend(item) {
  if (allTrendsSelected()) return true;
  const kind = trendKind(item);
  return Boolean(kind && selectedTrends.has(kind));
}

function primaryCategoryList(categories) {
  return categories.filter(category => category !== "Animation");
}

function getVisibleYearInfo() {
  return data.years
    .map(yearInfo => {
      const count = (byYear.get(yearInfo.year) || []).filter(item => itemMatchesCategory(item) && itemMatchesTrend(item)).length;
      return { year: yearInfo.year, count };
    })
    .filter(yearInfo => yearInfo.count > 0);
}

function renderYearNavigation() {
  const visibleYears = getVisibleYearInfo();
  yearNav.textContent = "";
  yearSelect.textContent = "";

  const yearsByDecade = new Map();
  for (const yearInfo of visibleYears) {
    const option = document.createElement("option");
    option.value = String(yearInfo.year);
    option.textContent = `${yearInfo.year} (${yearInfo.count})`;
    yearSelect.appendChild(option);

    const decade = Math.floor(yearInfo.year / 10) * 10;
    if (!yearsByDecade.has(decade)) yearsByDecade.set(decade, []);
    yearsByDecade.get(decade).push(yearInfo);
  }

  for (const [decade, years] of yearsByDecade) {
    const details = document.createElement("details");
    details.className = "decade-group";
    details.dataset.decade = String(decade);
    details.open = decade === Math.floor(visibleYears[0].year / 10) * 10;
    const decadeCount = years.reduce((sum, year) => sum + year.count, 0);
    details.innerHTML = `
      <summary><span>${decade}s</span><span class="decade-count">${decadeCount} series</span></summary>
      <div class="decade-years"></div>
    `;
    const decadeYears = details.querySelector(".decade-years");
    for (const yearInfo of years) {
      const link = document.createElement("a");
      link.href = `#year-${yearInfo.year}`;
      link.dataset.year = String(yearInfo.year);
      link.innerHTML = `<span>${yearInfo.year}</span><small>${yearInfo.count}</small>`;
      decadeYears.appendChild(link);
    }
    yearNav.appendChild(details);
  }

  yearCount.textContent = visibleYears.length.toLocaleString();
}

let sections = [];
let navLinks = [];
let renderedYearCount = 0;
let catalogFullyRendered = false;
let pendingCatalogRenderHandle = null;
let pendingCatalogRenderIsIdle = false;
const yearEntries = Array.from(byYear.entries());
const initialRenderYearCount = 8;
const renderBatchYearCount = 8;

const observer = new IntersectionObserver(entries => {
  const visible = entries
    .filter(entry => entry.isIntersecting)
    .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
  if (!visible) return;
  for (const link of navLinks) {
    link.classList.toggle("active", link.dataset.year === visible.target.dataset.year);
  }
  yearSelect.value = visible.target.dataset.year;
  const activeDecade = Math.floor(Number(visible.target.dataset.year) / 10) * 10;
  for (const decadeGroup of yearNav.querySelectorAll(".decade-group")) {
    decadeGroup.open = decadeGroup.dataset.decade === String(activeDecade);
  }
}, { rootMargin: "-15% 0px -65% 0px", threshold: [0.01, 0.2, 0.5] });

function scrollToYear(year) {
  const target = document.getElementById(`year-${year}`);
  if (target) {
    target.scrollIntoView({ behavior: "auto", block: "start" });
    history.replaceState(null, "", `#year-${year}`);
  }
}

function renderCatalogSection(year, items) {
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
      ${items.map(item => `
        <article class="card" tabindex="0" role="button" aria-label="Open details for ${escapeText(item.title)}" data-id="${escapeText(item.id)}" data-categories="${escapeText(item.categories.join(";"))}" data-primary-categories="${escapeText(primaryCategoryList(item.categories).join(";"))}" data-has-animation="${item.categories.includes("Animation") ? "1" : "0"}" data-trend="${escapeText(trendKind(item) || "")}" data-score="${escapeText(Number(item.score).toFixed(1))}" data-search="${escapeText(item.title.toLowerCase())}">
          ${renderPoster(item)}
          <div class="card-main">
            <div class="card-top">
              <div class="title-row">
                <h3 class="title">${escapeText(item.title)}</h3>
                <div class="rating" title="IMDb rating" style="${ratingTone(item.score)}">IMDb ${escapeText(item.score.toFixed(1))}</div>
              </div>
              <div class="facts">
                ${item.categories.map(category => `<span class="fact category-chip">${escapeText(category)}</span>`).join("")}
                <span class="fact">${escapeText(item.seasonLabel)}</span>
                <span class="fact">${escapeText(item.years)}</span>
                <span class="fact">${escapeText(item.primaryOrigin)}</span>
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

function appendCatalogSections(targetCount) {
  const end = Math.min(targetCount, yearEntries.length);
  const fragment = document.createDocumentFragment();
  const newSections = [];
  for (let index = renderedYearCount; index < end; index++) {
    const [year, items] = yearEntries[index];
    const section = renderCatalogSection(year, items);
    fragment.appendChild(section);
    newSections.push(section);
  }

  catalog.appendChild(fragment);
  for (const section of newSections) {
    sections.push(section);
    observer.observe(section);
  }
  renderedYearCount = end;
  catalogFullyRendered = renderedYearCount >= yearEntries.length;
}

function scheduleCatalogRender() {
  if (catalogFullyRendered || pendingCatalogRenderHandle !== null) return;

  const renderNextBatch = deadline => {
    pendingCatalogRenderHandle = null;
    pendingCatalogRenderIsIdle = false;
    const hasIdleBudget = () => !deadline || deadline.timeRemaining() > 4;

    do {
      appendCatalogSections(renderedYearCount + renderBatchYearCount);
    } while (!catalogFullyRendered && hasIdleBudget());

    scheduleCatalogRender();
  };

  if ("requestIdleCallback" in window) {
    pendingCatalogRenderIsIdle = true;
    pendingCatalogRenderHandle = window.requestIdleCallback(renderNextBatch, { timeout: 500 });
  } else {
    pendingCatalogRenderHandle = window.setTimeout(() => renderNextBatch(null), 16);
  }
}

function cancelScheduledCatalogRender() {
  if (pendingCatalogRenderHandle === null) return;
  if (pendingCatalogRenderIsIdle && "cancelIdleCallback" in window) {
    window.cancelIdleCallback(pendingCatalogRenderHandle);
  } else {
    window.clearTimeout(pendingCatalogRenderHandle);
  }
  pendingCatalogRenderHandle = null;
  pendingCatalogRenderIsIdle = false;
}

function ensureCatalogRendered() {
  if (catalogFullyRendered) return;
  cancelScheduledCatalogRender();
  appendCatalogSections(yearEntries.length);
}

function renderCatalogSections() {
  cancelScheduledCatalogRender();
  for (const section of sections) {
    observer.unobserve(section);
  }
  catalog.textContent = "";
  sections = [];
  renderedYearCount = 0;
  catalogFullyRendered = false;
  appendCatalogSections(initialRenderYearCount);
  scheduleCatalogRender();
}

renderYearNavigation();
navLinks = Array.from(yearNav.querySelectorAll("a"));
renderCatalogSections();

yearSelect.addEventListener("change", () => {
  ensureCatalogRendered();
  scrollToYear(yearSelect.value);
});

yearNav.addEventListener("click", event => {
  const link = event.target.closest("a[data-year]");
  if (!link) return;
  event.preventDefault();
  ensureCatalogRendered();
  scrollToYear(link.dataset.year);
});

function renderDetailPoster(item) {
  if (!item.poster) {
    return `<div class="series-detail-poster"><div class="poster-fallback">No poster</div></div>`;
  }
  return `<div class="series-detail-poster"><img src="${escapeText(item.poster)}" alt="Poster for ${escapeText(item.title)}"></div>`;
}

function renderSeasonDetails(item) {
  const seasons = item.seasonDetails || [];
  if (!seasons.length) {
    return `
      <section class="season-detail">
        <h3>Seasons</h3>
        <p class="update-log-empty">No season details available.</p>
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

async function getSeriesDetail(item) {
  if (!detailsPromise) {
    detailsPromise = loadSeriesDetails().then(details => {
      detailsById = details.series || {};
      return detailsById;
    }).catch(error => {
      detailsPromise = null;
      detailsById = null;
      throw error;
    });
  }

  try {
    const detailMap = detailsById || await detailsPromise;
    return {
      ...item,
      ...(detailMap[item.id] || {}),
    };
  } catch (error) {
    console.error(error);
    return item;
  }
}

async function openSeriesDetail(item, trigger) {
  lastSeriesTrigger = trigger || null;
  const detailItem = await getSeriesDetail(item);
  seriesDetailBody.innerHTML = `
    <div class="detail-layout">
      <div class="detail-poster-frame">${renderDetailPoster(detailItem)}</div>
      <section class="detail-info" aria-labelledby="seriesDetailTitle">
        <div class="title-row">
          <h2 class="title" id="seriesDetailTitle">${escapeText(detailItem.title)}</h2>
          <div class="detail-title-actions">
            <div class="rating" title="IMDb rating" style="${ratingTone(detailItem.score)}">IMDb ${escapeText(Number(detailItem.score).toFixed(1))}</div>
            <button type="button" class="series-detail-close" id="seriesDetailClose" aria-label="Close series details">&times;</button>
          </div>
        </div>
        <div class="facts">
          ${(detailItem.categories || []).map(category => `<span class="fact category-chip">${escapeText(category)}</span>`).join("")}
          <span class="fact">${escapeText(detailItem.seasonLabel || detailItem.seasons || "-")}</span>
          <span class="fact">${escapeText(detailItem.years || "-")}</span>
          <span class="fact">${escapeText(detailItem.primaryOrigin || "-")}</span>
        </div>
        <div class="card-actions">
          ${renderTrendTag(detailItem)}
        </div>
      </section>
      <p class="detail-synopsis">${escapeText(detailItem.synopsis || "No synopsis available.")}</p>
      <div class="detail-season-panel">
        ${renderSeasonDetails(detailItem)}
      </div>
    </div>
  `;
  lockPageScroll();
  seriesDetailModal.hidden = false;
  document.getElementById("seriesDetailClose").focus();
}

function lockPageScroll() {
  if (document.body.classList.contains("modal-open")) return;
  lockedScrollY = window.scrollY;
  document.documentElement.classList.add("modal-open");
  document.body.classList.add("modal-open");
  document.body.style.top = `-${lockedScrollY}px`;
}

function unlockPageScroll() {
  if (!document.body.classList.contains("modal-open")) return;
  document.documentElement.classList.remove("modal-open");
  document.body.classList.remove("modal-open");
  document.body.style.top = "";
  window.scrollTo(0, lockedScrollY);
}

function restoreSeriesTriggerFocus() {
  if (!lastSeriesTrigger) return;
  try {
    lastSeriesTrigger.focus({ preventScroll: true });
  } catch {
    lastSeriesTrigger.focus();
  }
}

function closeSeriesDetail() {
  const restoreScrollY = lockedScrollY;
  seriesDetailModal.hidden = true;
  unlockPageScroll();
  restoreSeriesTriggerFocus();
  window.scrollTo(0, restoreScrollY);
  requestAnimationFrame(() => window.scrollTo(0, restoreScrollY));
}

function getModalFocusableElements() {
  return Array.from(seriesDetailModal.querySelectorAll(focusableSelectors))
    .filter(element => element.offsetParent !== null);
}

function trapModalFocus(event) {
  if (event.key !== "Tab" || seriesDetailModal.hidden) return;

  const focusable = getModalFocusableElements();
  if (!focusable.length) {
    event.preventDefault();
    return;
  }

  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (focusable.length === 1) {
    event.preventDefault();
    first.focus();
  } else if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

catalog.addEventListener("click", async event => {
  if (event.target.closest(".imdb-link")) return;
  const card = event.target.closest(".card");
  if (!card) return;
  const item = seriesById.get(card.dataset.id);
  if (item) await openSeriesDetail(item, card);
});

catalog.addEventListener("keydown", async event => {
  if (event.key !== "Enter" && event.key !== " ") return;
  const card = event.target.closest(".card");
  if (!card) return;
  event.preventDefault();
  const item = seriesById.get(card.dataset.id);
  if (item) await openSeriesDetail(item, card);
});

seriesDetailModal.addEventListener("click", event => {
  if (event.target === seriesDetailModal) closeSeriesDetail();
  if (event.target.id === "seriesDetailClose") closeSeriesDetail();
});

function cardMatchesCategory(card) {
  if (card.dataset.hasAnimation === "1" && !selectedCategories.has("Animation")) {
    return false;
  }

  const primaryCategories = `;${card.dataset.primaryCategories};`;
  for (const category of selectedCategories) {
    if (category !== "Animation" && primaryCategories.includes(`;${category};`)) {
      return true;
    }
  }
  return false;
}

function cardMatchesTrend(card) {
  if (allTrendsSelected()) return true;
  return Boolean(card.dataset.trend && selectedTrends.has(card.dataset.trend));
}

function parseScoreInput(input, fallback) {
  if (!input.value.trim()) return fallback;
  const value = Number(input.value);
  if (!Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(10, Math.round(value * 10) / 10));
}

function cardMatchesScore(card) {
  const score = Number(card.dataset.score);
  const minScore = parseScoreInput(minScoreInput, 1);
  const maxScore = parseScoreInput(maxScoreInput, 10);
  return score >= Math.min(minScore, maxScore) && score <= Math.max(minScore, maxScore);
}

let pendingFilterFrame = null;

function scheduleApplyFilters() {
  if (pendingFilterFrame !== null) {
    cancelAnimationFrame(pendingFilterFrame);
  }
  pendingFilterFrame = requestAnimationFrame(() => {
    pendingFilterFrame = null;
    applyFilters();
  });
}

function applyFilters() {
  if (pendingFilterFrame !== null) {
    cancelAnimationFrame(pendingFilterFrame);
    pendingFilterFrame = null;
  }
  ensureCatalogRendered();
  const query = search.value.trim().toLowerCase();
  const minHasValue = minScoreInput.value.trim().length > 0;
  const maxHasValue = maxScoreInput.value.trim().length > 0;
  const searching = query.length > 0 || !allCategoriesSelected() || !allTrendsSelected() || minHasValue || maxHasValue;
  document.body.classList.toggle("searching", searching);
  let visibleCards = 0;
  let visibleYears = 0;

  for (const section of sections) {
    let sectionVisible = 0;
    for (const card of section.querySelectorAll(".card")) {
      const match = cardMatchesCategory(card) && cardMatchesTrend(card) && cardMatchesScore(card) && (!query || card.dataset.search.includes(query));
      card.classList.toggle("hidden", !match);
      if (match) sectionVisible++;
    }
    section.classList.toggle("empty-year", sectionVisible === 0);
    visibleCards += sectionVisible;
    if (sectionVisible > 0) visibleYears++;
  }

  totalCount.textContent = visibleCards.toLocaleString();
  yearCount.textContent = visibleYears.toLocaleString();
  empty.classList.toggle("visible", searching && visibleCards === 0);
  metaLine.textContent = query || !allCategoriesSelected() || !allTrendsSelected() || minHasValue || maxHasValue ? `${visibleCards.toLocaleString()} matching series` : `Generated ${data.generatedAt}`;
}

function categorySelectionChanged() {
  selectedCategories = new Set(categoryChoices.filter(input => input.checked).map(input => input.value));
  updateCategoryTrigger();
  renderYearNavigation();
  navLinks = Array.from(yearNav.querySelectorAll("a"));
  applyFilters();
}

function trendSelectionChanged() {
  selectedTrends = new Set(trendChoices.filter(input => input.checked).map(input => input.value));
  updateTrendTrigger();
  renderYearNavigation();
  navLinks = Array.from(yearNav.querySelectorAll("a"));
  applyFilters();
}

function closeFilterMenu(filter, trigger, restoreFocus = false) {
  filter.classList.remove("open");
  trigger.setAttribute("aria-expanded", "false");
  if (restoreFocus) trigger.focus();
}

function closeOpenFilterMenu(restoreFocus = false) {
  if (categoryFilter.classList.contains("open")) {
    closeFilterMenu(categoryFilter, categoryTrigger, restoreFocus);
    return true;
  }
  if (trendFilter.classList.contains("open")) {
    closeFilterMenu(trendFilter, trendTrigger, restoreFocus);
    return true;
  }
  return false;
}

categoryTrigger.addEventListener("click", () => {
  const isOpen = categoryFilter.classList.toggle("open");
  categoryTrigger.setAttribute("aria-expanded", String(isOpen));
  closeFilterMenu(trendFilter, trendTrigger);
});

trendTrigger.addEventListener("click", () => {
  const isOpen = trendFilter.classList.toggle("open");
  trendTrigger.setAttribute("aria-expanded", String(isOpen));
  closeFilterMenu(categoryFilter, categoryTrigger);
});

categoryAll.addEventListener("change", () => {
  for (const input of categoryChoices) {
    input.checked = categoryAll.checked;
  }
  categorySelectionChanged();
});

trendAll.addEventListener("change", () => {
  for (const input of trendChoices) {
    input.checked = trendAll.checked;
  }
  trendSelectionChanged();
});

for (const input of categoryChoices) {
  input.addEventListener("change", () => {
    categorySelectionChanged();
  });
}

for (const input of trendChoices) {
  input.addEventListener("change", () => {
    trendSelectionChanged();
  });
}

document.addEventListener("click", event => {
  if (!categoryFilter.contains(event.target)) {
    closeFilterMenu(categoryFilter, categoryTrigger);
  }
  if (!trendFilter.contains(event.target)) {
    closeFilterMenu(trendFilter, trendTrigger);
  }
});

search.addEventListener("input", () => {
  scheduleApplyFilters();
});
minScoreInput.addEventListener("input", scheduleApplyFilters);
maxScoreInput.addEventListener("input", scheduleApplyFilters);

document.addEventListener("keydown", event => {
  if (event.key === "Escape" && !seriesDetailModal.hidden) {
    closeSeriesDetail();
  } else if (event.key === "Escape" && closeOpenFilterMenu(true)) {
    event.preventDefault();
  }
  trapModalFocus(event);
});
