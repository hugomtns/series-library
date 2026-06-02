# Orbital Catalog UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Orbital Catalog redesign for the static Series Library frontend.

**Architecture:** Keep the vanilla static frontend and existing data/filter behavior. Move the visual language into a tokenized CSS system, then adjust HTML/rendered markup only where needed for structure, accessibility labels, or styling hooks.

**Tech Stack:** Static HTML, CSS with OKLCH tokens, vanilla ES modules, existing PowerShell/Node verification scripts.

---

## File Structure

- Modify `series_library.css`: design tokens, layout, components, responsive behavior, motion, modal polish.
- Modify `series_library.html`: minimal shell text/class additions for the control rail and search header.
- Modify `series_library_rendering.js`: card/detail markup hooks for poster-forward media records and technical metadata.
- Do not modify `series_library.js` unless a class hook is required for styling while preserving behavior.
- Do not modify data files, SQLite, server, or scripts.

## Task 1: Baseline Guard

**Files:**
- Read: `series_library.html`
- Read: `series_library.css`
- Read: `series_library_rendering.js`
- Test: existing `npm test`

- [x] **Step 1: Run current verification**

Run: `npm test`

Expected: PASS. If it fails before edits, record the failure and do not treat it as caused by the redesign.

- [x] **Step 2: Confirm forbidden UI/API strings are absent**

Run: `rg -n "/api/update|EventSource|update button|Browser update" series_library.html series_library.js series_library_rendering.js series_library.css`

Expected: no matches.

## Task 2: Tokenized Orbital Theme

**Files:**
- Modify: `series_library.css`

- [x] **Step 1: Replace root tokens**

Replace the current `:root` block with tokens for dark tinted surfaces, shared control states, semantic trend colors, and easing:

```css
:root {
  color-scheme: dark;
  --bg: oklch(13.5% 0.014 238);
  --bg-2: oklch(16% 0.018 238);
  --rail: oklch(18% 0.02 238);
  --surface: oklch(21% 0.018 238);
  --surface-2: oklch(25% 0.02 238);
  --surface-3: oklch(29% 0.023 238);
  --ink: oklch(93% 0.012 230);
  --muted: oklch(69% 0.02 230);
  --faint: oklch(52% 0.02 230);
  --line: oklch(34% 0.022 238);
  --line-soft: oklch(28% 0.02 238);
  --accent: oklch(72% 0.16 194);
  --accent-strong: oklch(78% 0.18 194);
  --accent-soft: oklch(28% 0.07 194);
  --control-bg: oklch(18.5% 0.018 238);
  --control-border: oklch(37% 0.03 238);
  --control-hover: oklch(24% 0.026 238);
  --focus: oklch(76% 0.18 194);
  --focus-ring: 0 0 0 3px oklch(76% 0.18 194 / 0.22);
  --active-shift: translateY(1px);
  --shadow: 0 18px 55px oklch(8% 0.02 238 / 0.42);
  --ease-out-quart: cubic-bezier(0.25, 1, 0.5, 1);
  --ease-out-quint: cubic-bezier(0.22, 1, 0.36, 1);
}
```

- [x] **Step 2: Standardize base typography**

Keep the system stack but add `font-variant-numeric: tabular-nums;` to numeric-heavy elements: `.stat strong`, `.rating`, `.year-heading h2`, `.season-score`, `.season-row`.

- [x] **Step 3: Verify CSS has no banned gradient text or side-stripe accents**

Run: `rg -n "background-clip:\\s*text|border-left:\\s*[2-9]" series_library.css`

Expected: no matches. The stylesheet keeps 2px right/bottom borders only for native chevron indicators.

## Task 3: Control Rail And Header

**Files:**
- Modify: `series_library.html`
- Modify: `series_library.css`

- [x] **Step 1: Add terse brand metadata**

In `series_library.html`, inside `.brand`, keep `h1` and add:

```html
<p class="brand-kicker">Static IMDb genre archive</p>
```

- [x] **Step 2: Style rail as command deck**

Update `.sidebar`, `.brand`, `.stats`, `.stat`, `.filter-panel`, `.filter-summary`, `.toolbar`, `.search`, `.meta-line`, controls, and reset buttons so they use the new token system and dark control language.

- [x] **Step 3: Preserve mobile filter behavior**

Keep `#filterPanel` as `<details>` and preserve `#filterPanelState`. On mobile, `.filter-summary` remains visible with at least 44px height.

- [x] **Step 4: Run static string check**

Run: `rg -n "brand-kicker|filterPanelState|categoryTrigger|trendTrigger" series_library.html series_library.js`

Expected: all existing IDs still present, plus `brand-kicker` in HTML.

## Task 4: Catalog Media Records

**Files:**
- Modify: `series_library_rendering.js`
- Modify: `series_library.css`

- [x] **Step 1: Add structural hooks to card markup**

In `renderCatalogSection`, keep all data attributes and add wrapper classes only:

```html
<div class="card-main">
  <div class="card-top">
    <div class="title-row">...</div>
    <div class="facts meta-stack">...</div>
  </div>
  <div class="card-actions">...</div>
</div>
```

The required attributes remain: `data-id`, `data-primary-categories`, `data-has-animation`, `data-trend`, `data-score`, `data-rated-seasons`, `data-search`.

- [x] **Step 2: Restyle cards**

Cards become poster-forward media records:

```css
.card {
  grid-template-columns: 96px minmax(0, 1fr);
  min-height: 158px;
  background: linear-gradient(135deg, var(--surface), var(--surface-2));
}
```

Keep card radius at 8px or less, stable poster aspect ratio, and keyboard focus visibility.

- [x] **Step 3: Improve chips without changing labels**

Style `.fact`, `.category-chip`, `.rating`, `.trend-tag`, `.imdb-link` for high contrast on dark surfaces. Do not change text content: category names, `IMDb`, `Trend Up`, `Trend Down`, `Disaster`.

- [x] **Step 4: Verify card behavior hooks**

Run: `rg -n "article class=\\\"card\\\"|data-rated-seasons|imdb-link|renderTrendTag" series_library_rendering.js`

Expected: all match.

## Task 5: Detail Modal

**Files:**
- Modify: `series_library.css`
- Modify: `series_library_rendering.js` only if class hooks are needed

- [x] **Step 1: Restyle modal shell**

Use a dark raised modal, internal scroll, strong poster column, and compact metadata panel. Keep:

```html
<section class="series-detail-modal" role="dialog" aria-modal="true" aria-labelledby="seriesDetailTitle">
```

- [x] **Step 2: Keep modal controls intact**

Do not add a footer button. Preserve the close button with `id="seriesDetailClose"` and `aria-label="Close series details"`.

- [x] **Step 3: Restyle season table**

Use dark table rows, sticky-looking header treatment if possible without changing behavior, and keep columns: Season, Year, Episodes, IMDb avg.

- [x] **Step 4: Verify detail invariants**

Run: `rg -n "seriesDetailClose|detail-synopsis|season-table|IMDb avg|imdb-link" series_library.js series_library_rendering.js`

Expected: close/synopsis/season table present; `imdb-link` only in card rendering, not detail modal.

## Task 6: Responsive Polish

**Files:**
- Modify: `series_library.css`

- [x] **Step 1: Desktop check in CSS**

Keep `.shell` as a two-column grid above tablet widths. Sidebar remains sticky with `height: 100vh`.

- [x] **Step 2: Tablet/mobile check in CSS**

At `max-width: 980px`, collapse to one column. At `max-width: 620px`, ensure cards fit in one column, touch targets remain at least 44px, and detail layout uses poster/info then synopsis/seasons.

- [x] **Step 3: Prevent overflow**

Ensure long titles and facts wrap with `overflow-wrap: anywhere`, grid children use `min-width: 0`, and `.season-table` can scroll or compress on mobile.

- [x] **Step 4: Reduced motion check**

Keep the existing `@media (prefers-reduced-motion: reduce)` block and ensure new animations/transitions are covered by it.

## Task 7: Final Verification

**Files:**
- Test: `npm test`
- Inspect: `git diff`

- [x] **Step 1: Run full verification**

Run: `npm test`

Expected: PASS.

- [x] **Step 2: Run deploy-sensitive string check**

Run: `rg -n "/api/update|EventSource|Browser update|Done</button>|<style" series_library.html series_library.js series_library_rendering.js series_library.css`

Expected: no matches.

- [x] **Step 3: Review changed files**

Run: `git diff -- series_library.html series_library.css series_library_rendering.js`

Expected: visual/refactor changes only, no data pipeline or server changes.

- [x] **Step 4: Commit implementation**

Run:

```powershell
git add series_library.html series_library.css series_library_rendering.js docs/superpowers/plans/2026-06-02-orbital-catalog-ui.md
git commit -m "feat: redesign catalog UI"
```
