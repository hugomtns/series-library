# Orbital Catalog Design

## Goal

Redesign Series Library into a distinctive, minimal, futuristic catalog browser without changing the static data contract or public behavior. The interface should feel like a precise media archive: dense, fast, poster-forward, and controlled by the user.

## Product Constraints

- Keep the app static. No browser-side update controls, mutable APIs, or progress streams.
- Preserve current filters: title search, category, trend, IMDb score range, rated-season count range, year jump, and decade browsing.
- Preserve card keyboard behavior, modal focus trap, Escape handling, lazy detail loading, and static JSON loading.
- Keep the frontend vanilla HTML, CSS, and JavaScript. No framework migration.
- Keep mobile first-class. Filters may collapse, but browsing and searching must stay ergonomic.

## Visual Direction

Use an "Orbital Catalog" language:

- Dark, tinted-neutral base with one electric cyan/teal accent and semantic trend colors.
- Poster art becomes the main visual texture; chrome stays restrained.
- Controls feel like a compact command deck, not generic form fields.
- Metadata uses tabular, technical treatment without sacrificing readability.
- Motion is short and state-driven: hover lift, menu reveal, modal entry, active filter feedback.

Physical scene: a viewer or maintainer is scanning a large genre catalog at night on desktop or phone, trying to find a promising series quickly without algorithmic noise. This supports a dark UI with high contrast, precise states, and low decorative clutter.

## Design System

Create a small CSS design system in `series_library.css`.

Token groups:

- Color: app background, rail, surface, raised surface, border, subtle border, text, muted text, accent, accent-soft, focus, danger, warning, success.
- Type: system UI stack, compact label size, body size, card title size, section heading size, tabular numeric treatment.
- Radius: controls and cards at 8px or less; circular buttons only where appropriate.
- Spacing: tight control spacing, card gap, section rhythm, modal padding.
- Motion: 120-240ms transitions using quart/quint/expo style easing; reduced-motion override remains.
- Shadow: minimal raised states for dropdowns and modal only.

Component classes:

- Shared control treatment for search, select, dropdown triggers, numeric inputs, reset buttons.
- Filter menu/options with stronger selected/focus states.
- Stats as compact telemetry cells, not generic cards.
- Year navigation as a compact timeline/decade control.
- Catalog cards as media records with stable poster sizing, stronger hover/focus affordance, and aligned metadata.
- Trend/rating chips remain semantic and legible.
- Detail modal uses a cinematic two-column layout on desktop and compact poster/info layout on mobile.

## Layout

Desktop:

- Keep the sticky left rail, but make it feel like a persistent control deck.
- Main header remains sticky with search and result status.
- Catalog sections keep year grouping, but headings should feel like timeline markers.
- Cards remain dense enough for scanning, but become more visually distinctive through poster contrast, title hierarchy, and metadata alignment.

Mobile:

- Sidebar becomes a top control block with collapsible filters.
- Search remains prominent and full width.
- Cards become single-column media rows with stable touch targets.
- Detail modal uses nearly full viewport width, scrolls internally, and keeps the close control easy to reach.

## Interaction And Motion

- Add visible state transitions for controls, cards, dropdowns, decade groups, and modal open/close.
- Use transform and opacity only for motion.
- Respect `prefers-reduced-motion`.
- Do not animate initial page load with choreography.
- Do not introduce custom controls that break native keyboard behavior.

## Frontend Refactor Scope

Refactor only where it supports the design system:

- Consolidate repeated CSS declarations into tokens and shared selectors.
- Adjust HTML class hooks only if necessary for layout or component clarity.
- Update rendering helper markup only for card/detail structure and class naming needed by the design.
- Do not change data loading, filtering semantics, trend logic, or server behavior.

## Verification

- Run `npm test`.
- Manually inspect desktop and mobile layouts if browser tooling is available.
- Check that search, filters, reset, year jumping, card open, modal close, and season table remain intact.
- Confirm there are still no browser update controls or `/api/update` references.
