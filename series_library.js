import { loadCatalogData, loadSeriesDetails } from "./series_library_data_client.js";
import {
  escapeText,
  ratingTone,
  renderCatalogSection,
  renderDetailPoster,
  renderSeasonDetails,
  renderTrendTag,
  trendKind,
} from "./series_library_rendering.js";

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
const filterPanelState = document.getElementById("filterPanelState");
const trendFilter = document.getElementById("trendFilter");
const trendTrigger = document.getElementById("trendTrigger");
const trendAll = document.getElementById("trendAll");
const trendChoices = Array.from(document.querySelectorAll(".trend-choice"));
const minScoreInput = document.getElementById("minScore");
const maxScoreInput = document.getElementById("maxScore");
const filterStatus = document.getElementById("filterStatus");
const resetFilters = document.getElementById("resetFilters");
const seriesDetailModal = document.getElementById("seriesDetailModal");
const seriesDetailBody = document.getElementById("seriesDetailBody");
const catalog = document.getElementById("catalog");
const totalCount = document.getElementById("totalCount");
const yearCount = document.getElementById("yearCount");
const metaLine = document.getElementById("metaLine");
const search = document.getElementById("search");
const empty = document.getElementById("empty");
const emptyTitle = document.getElementById("emptyTitle");
const emptyMessage = document.getElementById("emptyMessage");
const emptyReset = document.getElementById("emptyReset");

let selectedCategories = new Set(categoryChoices.map(input => input.value));
let selectedTrends = new Set(trendChoices.map(input => input.value));
let lastSeriesTrigger = null;
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
  syncFilterPanelState();
}

function syncFilterPanelState() {
  filterPanelState.textContent = filterPanel.open ? "Close" : "Open";
}

syncFilterPanelForViewport();
mobileFilterQuery.addEventListener("change", syncFilterPanelForViewport);
filterPanel.addEventListener("toggle", syncFilterPanelState);

totalCount.textContent = data.total.toLocaleString();
yearCount.textContent = data.years.length.toLocaleString();
metaLine.textContent = `Generated ${data.generatedAt}`;

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
  } else if (selectedCategories.size === 1) {
    categoryTrigger.textContent = Array.from(selectedCategories)[0];
    categoryAll.checked = false;
  } else {
    categoryTrigger.textContent = `${selectedCategories.size} categories selected`;
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
  } else if (selectedTrends.size === 1) {
    trendTrigger.textContent = labels[Array.from(selectedTrends)[0]];
    trendAll.checked = false;
  } else {
    trendTrigger.textContent = `${selectedTrends.size} trends selected`;
    trendAll.checked = false;
  }

  for (const input of trendChoices) {
    input.checked = selectedTrends.has(input.value);
  }
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
let activeYearJumpTarget = null;
const yearEntries = Array.from(byYear.entries());
const initialRenderYearCount = 8;
const renderBatchYearCount = 8;
const priorityPosterBudgetStart = 8;
let priorityPosterBudget = priorityPosterBudgetStart;

function setActiveYear(year) {
  for (const link of navLinks) {
    link.classList.toggle("active", link.dataset.year === String(year));
  }
  yearSelect.value = String(year);
  const activeDecade = Math.floor(Number(year) / 10) * 10;
  for (const decadeGroup of yearNav.querySelectorAll(".decade-group")) {
    decadeGroup.open = decadeGroup.dataset.decade === String(activeDecade);
  }
}

const observer = new IntersectionObserver(entries => {
  if (activeYearJumpTarget) return;
  const visible = entries
    .filter(entry => entry.isIntersecting)
    .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
  if (!visible) return;
  setActiveYear(visible.target.dataset.year);
}, { rootMargin: "-15% 0px -65% 0px", threshold: [0.01, 0.2, 0.5] });

function scrollToYear(year) {
  const target = document.getElementById(`year-${year}`);
  if (target) {
    activeYearJumpTarget = String(year);
    setActiveYear(year);
    document.body.classList.add("year-jumping");
    const previousScrollBehavior = document.documentElement.style.scrollBehavior;
    document.documentElement.style.scrollBehavior = "auto";
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        target.scrollIntoView({ behavior: "auto", block: "start" });
        document.documentElement.style.scrollBehavior = previousScrollBehavior;
        history.replaceState(null, "", `#year-${year}`);
        window.setTimeout(() => {
          document.body.classList.remove("year-jumping");
          activeYearJumpTarget = null;
          setActiveYear(year);
        }, 500);
      });
    });
  }
}

function appendCatalogSections(targetCount) {
  const end = Math.min(targetCount, yearEntries.length);
  const fragment = document.createDocumentFragment();
  const newSections = [];
  for (let index = renderedYearCount; index < end; index++) {
    const [year, items] = yearEntries[index];
    const priorityPosterCount = Math.min(priorityPosterBudget, items.length);
    const section = renderCatalogSection(year, items, { priorityPosterCount });
    priorityPosterBudget -= priorityPosterCount;
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
  priorityPosterBudget = priorityPosterBudgetStart;
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
  document.documentElement.classList.add("modal-open");
  document.body.classList.add("modal-open");
}

function unlockPageScroll() {
  if (!document.body.classList.contains("modal-open")) return;
  document.documentElement.classList.remove("modal-open");
  document.body.classList.remove("modal-open");
}

function closeSeriesDetail() {
  const modalScrollY = window.scrollY;
  seriesDetailModal.hidden = true;
  unlockPageScroll();
  window.scrollTo(0, modalScrollY);
  lastSeriesTrigger = null;
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

function handlePosterImageError(event) {
  const image = event.target;
  if (!(image instanceof HTMLImageElement)) return;
  const frame = image.closest(".poster, .series-detail-poster");
  if (!frame) return;
  frame.textContent = "";
  const fallback = document.createElement("div");
  fallback.className = "poster-fallback";
  fallback.textContent = "No poster";
  frame.appendChild(fallback);
}

catalog.addEventListener("error", handlePosterImageError, true);
seriesDetailModal.addEventListener("error", handlePosterImageError, true);

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

function hasActiveFilters() {
  return search.value.trim().length > 0 ||
    !allCategoriesSelected() ||
    !allTrendsSelected() ||
    minScoreInput.value.trim().length > 0 ||
    maxScoreInput.value.trim().length > 0;
}

function updateFilterStatus(visibleCards = data.total) {
  const active = [];
  if (search.value.trim()) active.push("title search");
  if (!allCategoriesSelected()) active.push(selectedCategories.size === 1 ? "1 category" : `${selectedCategories.size} categories`);
  if (!allTrendsSelected()) active.push(selectedTrends.size === 1 ? "1 trend" : `${selectedTrends.size} trends`);
  if (minScoreInput.value.trim() || maxScoreInput.value.trim()) active.push("score range");

  resetFilters.disabled = active.length === 0;
  filterStatus.textContent = active.length
    ? `${visibleCards.toLocaleString()} matches: ${active.join(", ")}`
    : "No filters active";
}

function updateEmptyState(query) {
  if (selectedCategories.size === 0) {
    emptyTitle.textContent = "No categories selected";
    emptyMessage.textContent = "Select at least one category or reset filters.";
  } else if (selectedTrends.size === 0) {
    emptyTitle.textContent = "No trends selected";
    emptyMessage.textContent = "Select at least one trend label or reset filters.";
  } else if (query) {
    emptyTitle.textContent = "No title matches";
    emptyMessage.textContent = `No series title contains "${query}".`;
  } else if (minScoreInput.value.trim() || maxScoreInput.value.trim()) {
    emptyTitle.textContent = "No scores in range";
    emptyMessage.textContent = "Widen the score range or reset filters.";
  } else {
    emptyTitle.textContent = "No matching series";
    emptyMessage.textContent = "Try widening the current filters.";
  }
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
  const searching = hasActiveFilters();
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
  updateEmptyState(query);
  metaLine.textContent = query || !allCategoriesSelected() || !allTrendsSelected() || minHasValue || maxHasValue ? `${visibleCards.toLocaleString()} matching series` : `Generated ${data.generatedAt}`;
  updateFilterStatus(visibleCards);
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

function openFilterMenu(filter, trigger) {
  filter.classList.add("open");
  trigger.setAttribute("aria-expanded", "true");
}

function getFilterMenuInputs(filter) {
  return Array.from(filter.querySelectorAll(".category-menu input"));
}

function focusFilterMenuInput(filter, index) {
  const inputs = getFilterMenuInputs(filter);
  if (!inputs.length) return;
  const nextIndex = (index + inputs.length) % inputs.length;
  inputs[nextIndex].focus();
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

function toggleFilterMenu(filter, trigger, otherFilter, otherTrigger) {
  const isOpen = !filter.classList.contains("open");
  if (isOpen) {
    openFilterMenu(filter, trigger);
  } else {
    closeFilterMenu(filter, trigger);
  }
  closeFilterMenu(otherFilter, otherTrigger);
}

function handleFilterTriggerKeydown(event, filter, trigger, otherFilter, otherTrigger) {
  if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
  event.preventDefault();
  openFilterMenu(filter, trigger);
  closeFilterMenu(otherFilter, otherTrigger);
  focusFilterMenuInput(filter, event.key === "ArrowUp" ? -1 : 0);
}

function handleFilterMenuKeydown(event, filter, trigger) {
  if (event.target === trigger) return;
  const inputs = getFilterMenuInputs(filter);
  const currentIndex = inputs.indexOf(document.activeElement);
  if (currentIndex === -1) return;

  if (event.key === "ArrowDown" || event.key === "ArrowRight") {
    event.preventDefault();
    focusFilterMenuInput(filter, currentIndex + 1);
  } else if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
    event.preventDefault();
    focusFilterMenuInput(filter, currentIndex - 1);
  } else if (event.key === "Home") {
    event.preventDefault();
    focusFilterMenuInput(filter, 0);
  } else if (event.key === "End") {
    event.preventDefault();
    focusFilterMenuInput(filter, inputs.length - 1);
  } else if (event.key === "Enter") {
    event.preventDefault();
    document.activeElement.click();
  } else if (event.key === "Escape") {
    event.preventDefault();
    closeFilterMenu(filter, trigger, true);
  }
}

categoryTrigger.addEventListener("click", () => {
  toggleFilterMenu(categoryFilter, categoryTrigger, trendFilter, trendTrigger);
});

trendTrigger.addEventListener("click", () => {
  toggleFilterMenu(trendFilter, trendTrigger, categoryFilter, categoryTrigger);
});

categoryTrigger.addEventListener("keydown", event => {
  handleFilterTriggerKeydown(event, categoryFilter, categoryTrigger, trendFilter, trendTrigger);
});

trendTrigger.addEventListener("keydown", event => {
  handleFilterTriggerKeydown(event, trendFilter, trendTrigger, categoryFilter, categoryTrigger);
});

categoryFilter.addEventListener("keydown", event => {
  handleFilterMenuKeydown(event, categoryFilter, categoryTrigger);
});

trendFilter.addEventListener("keydown", event => {
  handleFilterMenuKeydown(event, trendFilter, trendTrigger);
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

function resetAllFilters() {
  search.value = "";
  minScoreInput.value = "";
  maxScoreInput.value = "";
  selectedCategories = new Set(categoryChoices.map(input => input.value));
  selectedTrends = new Set(trendChoices.map(input => input.value));
  updateCategoryTrigger();
  updateTrendTrigger();
  renderYearNavigation();
  navLinks = Array.from(yearNav.querySelectorAll("a"));
  applyFilters();
}

resetFilters.addEventListener("click", resetAllFilters);
emptyReset.addEventListener("click", resetAllFilters);

document.addEventListener("keydown", event => {
  if (event.key === "Escape" && !seriesDetailModal.hidden) {
    closeSeriesDetail();
  } else if (event.key === "Escape" && closeOpenFilterMenu(true)) {
    event.preventDefault();
  }
  trapModalFocus(event);
});
