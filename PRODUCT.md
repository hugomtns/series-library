# Series Library Product Context

## Register

Product UI.

## Product Purpose

Series Library is a static browsing tool for IMDb-rated genre TV series. It helps a user scan eligible series by year, title, category, score range, rated-season count, and season-rating trend without waiting on live API calls.

The app is intentionally static on Vercel. Data updates happen through CLI workflows only; the browser must never expose update controls or mutable data operations.

## Primary Users

- A catalog maintainer checking that the dataset is complete, ranked, and trend-labeled correctly.
- A viewer browsing genre TV by release year and filtering quickly to find candidates.
- A developer maintaining the static export and UI without needing a backend service.

## Core Workflows

- Browse ranked series by year.
- Filter by source category, secondary animation tag, trend label, title search, score range, and rated-season count range.
- Jump to a year or decade.
- Open a detail modal to inspect synopsis and season breakdown.
- Leave the app and data immutable from the public browser.

## Product Principles

- Static-first: committed JSON is the public contract.
- Dense but calm: prioritize scanning, comparison, and repeated browsing.
- Familiar controls: standard inputs and predictable navigation beat novelty.
- Fast perceived performance: render the first useful catalog quickly, defer the rest.
- Clear provenance: IMDb ids, ratings, years, country origin, categories, rated-season counts, and trends should be easy to inspect.

## Anti-References

- Landing-page styling, oversized hero composition, or marketing copy.
- Decorative cards, nested cards, and gratuitous animation.
- Browser-side update actions, progress streams, or hidden mutable APIs.
- Search behavior that silently expands beyond titles.
- Modal detail layouts that duplicate card metadata or add extra action bars.

## Quality Bar

Production utility. The interface should feel stable, restrained, and trustworthy rather than flashy. UI improvements should standardize existing patterns before adding new visual language.
