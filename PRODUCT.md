# Series Library Product Context

## Register

Product UI.

## Product Purpose

Series Library is a static catalog browsing tool for IMDb-rated genre TV series across Sci-Fi, Fantasy, Adventure, Action, and Comedy. It helps a user scan eligible series by year, title, source category, secondary Animation tag, score range, rated-season count, season-rating trend, and personal tags without waiting on live IMDb API calls.

The catalog is intentionally static on Vercel. Catalog data updates happen through CLI workflows only; the browser must never expose catalog update controls. Personal tags are mutable through a small API so they can follow a user across devices.

## Primary Users

- A catalog maintainer checking that the dataset is complete, ranked, and trend-labeled correctly.
- A viewer browsing genre TV by release year and filtering quickly to find candidates.
- A developer maintaining the static export, UI, and small personal-state API.

## Core Workflows

- Browse ranked series by year.
- Filter by source category, secondary animation tag, trend label, title search, score range, and rated-season count range.
- Filter by personal tags: Wishlisted, Available, and Seen.
- Sync Available and Seen from a local Plex TV library through CLI tooling.
- Jump to a year or decade.
- Open a detail modal to inspect synopsis, season breakdown, and personal tag controls.
- Lazy-load modal-only synopsis and season details from the static detail payload.
- Return to the top of the series list with a non-intrusive floating control after scrolling deep into the catalog.
- Leave catalog data immutable from the public browser while allowing personal tag changes.

## Product Principles

- Static-first: committed JSON is the public contract.
- Compact index first: the public index stays small, and modal-only details live in the separate static detail payload.
- Personal state is separate: user-facing tags live in API-backed storage, not catalog JSON.
- Local media state is additive: Plex sync updates personal tags only and never mutates catalog data.
- Dense but calm: prioritize scanning, comparison, and repeated browsing.
- Poster-forward discovery: use the committed poster art as the main visual signal while keeping metadata compact and stable.
- Familiar controls: standard inputs and predictable navigation beat novelty.
- Fast perceived performance: render the first useful catalog quickly, defer the rest.
- Clear provenance: IMDb ids, ratings, years, country origin, source categories, secondary tags, rated-season counts, and trends should be easy to inspect.

## Anti-References

- Landing-page styling, oversized hero composition, or marketing copy.
- Decorative cards, nested cards, and gratuitous animation.
- Browser-side catalog update actions, progress streams, or hidden mutable catalog APIs.
- Search behavior that silently expands beyond titles.
- Public index bloat from modal-only synopsis or season details.
- Modal detail layouts that duplicate card metadata or add extra action bars.

## Quality Bar

Production utility. The interface should feel stable, restrained, distinctive, and trustworthy rather than flashy. UI improvements should preserve the static catalog contract, keep poster browsing fast, and avoid decoration that makes scrolling feel heavier.
