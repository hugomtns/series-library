# Series Library Agent Guide

## Response Style

- Be terse by default. State results and the next step only.
- Do not recap obvious diffs unless asked.
- No preamble for simple answers.
- Expand only when asked "why" or "explain".
- When asking for feedback, ask the shortest useful question.

## Project Purpose

This repo builds and serves a mostly static TV series library from IMDbAPI data, with API-backed personal series tags.

The public app lets users browse ranked eligible TV series by year, category, tag/trend label, title search, IMDb score range, and rated-season count range. Catalog data is static for Vercel: users must not be able to trigger IMDb/catalog data updates from the browser. Personal tags (`Wishlisted`, `Available`, `Seen`) are mutable through the series-state API.

Current tracked categories:

- `Sci-Fi`
- `Fantasy`
- `Adventure`
- `Action`
- `Comedy`
- `Animation` is derived from IMDb detail genres and used as a secondary filter/tag, not as a primary source category.

Eligibility is based on IMDbAPI title search results for TV series / TV mini series, with at least 5000 votes, primary-origin country limited to US/UK/Canada/Europe/Australia/New Zealand. Turkish-primary rows are excluded.

## Architecture

Primary runtime files:

- `series_library.html`: static frontend shell and markup.
- `series_library.css`: all UI styles.
- `series_library.js`: client-side app state, filtering, modal, and interaction logic.
- `series_library_rendering.js`: card, section, modal, and filter rendering helpers.
- `series_library_data_client.js`: static JSON loading and detail lookup helpers.
- `series_library_data.json`: static public index consumed by the frontend.
- `series_library_details.json`: static modal detail payload consumed on demand.
- `series_library.db`: SQLite source of truth for the exported public catalog.
- `api/series-state-store.js`: local SQLite and production Postgres adapters for personal tags.
- `api/series-state-handler.js`: shared API handler for personal tag state.
- `api/series-state.js` and `api/series-state/[imdbId].js`: Vercel API routes for personal tags.
- `series_library_server.js`: local static server plus local personal-tag API.
- `vercel.json`: Vercel rewrite from `/` to `/series_library.html` plus JSON cache header.

Data pipeline files:

- `collect_genre_primary_origin_years.ps1`: fetches per-year IMDbAPI source CSVs for a genre.
- `build_combined_genre_catalog_source.ps1`: combines category year CSVs into `scripts/.generated/catalog_source.csv`.
- `build_sci_fi_catalog_page.ps1`: enriches source rows from IMDbAPI/cache and writes `scripts/.generated/catalog_data.json`. The name is historical; it handles all categories.
- `scripts/migrate_to_sqlite.js`: migrates catalog JSON and cached season/episode data into SQLite.
- `scripts/export_public_catalog.js`: exports `series_library_data.json` from SQLite.
- `scripts/trend_rules.js`: shared rated-season and trend-label rules used by migration/export.
- `scripts/rebuild_catalog_and_db.ps1`: runs combine -> catalog JSON -> SQLite -> public JSON.
- `scripts/update_library.js`: full CLI update pipeline.
- `scripts/update_current_year_sources.ps1`: refreshes current-year source files for all configured categories.
- `scripts/refresh_open_series_seasons.ps1`: refreshes season and episode ratings.
- `scripts/refresh_existing_ratings.js`: refreshes cached title ratings.
- `scripts/preview_under_5k_near_misses.ps1`: near-miss report for under-5000-vote candidates.
- `scripts/report_season_rating_trends.js`: prints season trend slopes.
- `scripts/report_poster_delivery.js`: checks poster URL availability.
- `scripts/validate_public_json_schema.js`: validates compact public index/detail JSON shape.
- `scripts/check_deploy_ready.js`: checks Vercel/static deploy readiness.
- `scripts/check_local_server.js`: smoke-checks the local static server.
- `scripts/browser_regression_check.js`: optional browser regression check for the local UI.
- `verify_sci_fi_catalog_page.ps1`: main verification script. The name is historical; it verifies the whole app.

Generated files:

- `scripts/.generated/*` is ignored and can be regenerated.
- `imdb_sci_fi_catalog_cache/*` is ignored and stores title/season/episode cache.
- `series_user_state.db` is ignored local personal-tag state.
- `*.db-shm` and `*.db-wal` are ignored SQLite sidecar files.

Tracked data files:

- `series_library.db`
- `series_library_data.json`
- `series_library_details.json`
- primary-origin year CSVs under `imdb_*_year_files_primary_origin`

Avoid adding new raw JSON source files to git. Action source JSONs are explicitly ignored.

## Commands

Install dependencies:

```powershell
npm install
```

Run local static server:

```powershell
npm run serve
```

Default local URL:

```text
http://127.0.0.1:8787/
```

Run verification:

```powershell
npm test
```

Rebuild SQLite and public JSON from existing source/cache:

```powershell
npm run migrate
```

Full CLI update:

```powershell
npm run update
```

Export only public JSON from SQLite:

```powershell
npm run export
```

Print trend slopes:

```powershell
npm run trends
```

Refresh Action season/episode ratings only:

```powershell
npm run refresh:action-seasons
```

Refresh Comedy season/episode ratings only:

```powershell
npm run refresh:comedy-seasons
```

Check poster delivery:

```powershell
npm run posters:report
```

Collect a historical category source set, example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File collect_genre_primary_origin_years.ps1 -Genre Action -GenreLabel Action -FilePrefix imdb_action_primary_origin -OutYearDir imdb_action_year_files_primary_origin -StartYear 1960 -EndYear 2026 -SkipJson
```

Use `-SkipJson` unless there is a specific reason to write raw source JSON.

## Data Flow

1. Per-year category CSVs are collected from IMDbAPI into `imdb_*_year_files_primary_origin`.
2. `build_combined_genre_catalog_source.ps1` deduplicates by `Year + IMDbId`, merges categories, ranks each year, and writes generated source files.
3. `build_sci_fi_catalog_page.ps1` fetches/caches IMDb title details and seasons, then writes generated catalog JSON.
4. `scripts/migrate_to_sqlite.js` normalizes series, categories, genres, seasons, ratings, and trends into SQLite.
5. `scripts/export_public_catalog.js` exports compact `series_library_data.json` plus lazy-loaded modal payloads in `series_library_details.json`.
6. Vercel serves the static HTML/CSS/JS files plus `series_library_data.json` and `series_library_details.json`.
7. Personal tags are read and written through `/api/series-state`, backed by Postgres in production and `series_user_state.db` locally.

The browser never reads SQLite directly.

## Season Trend Rules

Trend labeling must use rated seasons only.

Algorithm:

1. Build ordered points from season rows where `score` is numeric and at least `0.1`.
2. If there are fewer than 3 rated seasons, show no trend label.
3. If the first rated season is at least `1.5` points higher than the last rated season, label `Disaster`.
4. Otherwise calculate linear regression `y = mx + b` on the rated season points.
5. If `m >= 0.3`, label `Trend Up`.
6. If `m <= -0.3`, label `Trend Down`.

`Disaster` supersedes `Trend Down`.

Important example:

- `The Witcher` must be `Disaster`.
- Its rated seasons are `8.3, 8.0, 5.8, 4.4`; unrated future seasons must be ignored.

The same trend semantics should be reflected in:

- `scripts/trend_rules.js`
- `scripts/migrate_to_sqlite.js`
- `scripts/export_public_catalog.js`
- `series_library.js` / `series_library_rendering.js` consuming exported `trendKind` and `trendSlope`
- `verify_sci_fi_catalog_page.ps1`
- regenerated `series_library.db`
- regenerated `series_library_data.json`
- regenerated `series_library_details.json` when detail payloads change

The rated-season count filter must use the same rated-season definition: season rows where `score` is numeric and at least `0.1`. Pending or unrated seasons do not count.

## Frontend Notes

The app is a static frontend in `series_library.html`.

Expected behavior:

- Load data using `fetch("series_library_data.json", { cache: "no-store" })`.
- Lazy-load modal detail payloads using `fetch("series_library_details.json", { cache: "no-store" })`.
- Load and save personal tags using `/api/series-state`.
- Search titles only, not synopsis.
- Cards are clickable and keyboard-openable detail triggers.
- Cards show compact metadata and the IMDb link.
- Detail modal shows poster, same card-style series info, personal tag toggles, synopsis, and season breakdown.
- Desktop catalog uses stable poster-wall cards; do not let metadata chips or actions clip.
- Detail modal should make efficient use of width, with poster and series information visible without a tall empty synopsis panel.
- Back-to-top/list control should stay non-intrusive, appear only after scrolling into the catalog, scroll to `#catalog`, respect reduced motion, and hide again near the list top on mobile.
- Detail modal must not duplicate the IMDb link.
- Detail modal uses only the close `X`, no footer "Done" button.
- Category and tag filters are multi-select dropdowns; the tag filter includes `Trend Up`, `Trend Down`, `Disaster`, `Wishlisted`, `Available`, and `Seen`.
- IMDb score and rated-season count filters are min/max range inputs.
- Trend and personal tags are rendered on both cards and detail modal.

Do not re-add:

- Browser catalog update button.
- `/api/update` references.
- `EventSource` progress UI.
- Inline `<style>` block.
- Card synopsis.
- Duplicate detail modal tag rows or metric boxes.
- Paint-heavy repeated card effects such as backdrop blur, per-card overlay pseudo-elements, or heavy shadows that make catalog scrolling sluggish.

## Vercel Deployment

The project is deployed as static catalog files plus Vercel API routes for personal tag state.

Vercel config:

- Framework preset: `Other`
- Root directory: `./`
- Build command: none required for the static files already committed.
- Output directory: default/root.

`vercel.json` rewrites `/` to `/series_library.html`.
It sets `Cache-Control: public, max-age=0, must-revalidate` for both public JSON files.

`.vercelignore` intentionally excludes:

- source/cache folders
- generated files
- SQLite DB
- node_modules
- local Vercel metadata

The deployed public catalog relies on committed `series_library_data.json` and `series_library_details.json`, not the SQLite DB. Personal tags require `DATABASE_URL` or `POSTGRES_URL` in Vercel.

## Update Policy

Catalog data updates happen through CLI commands only.

Do not add catalog update controls or mutable catalog data operations to the public UI. Personal tag mutation must stay limited to `Wishlisted`, `Available`, and `Seen`.

When changing data logic:

1. Update code/scripts.
2. Run the relevant refresh/rebuild command.
3. Commit regenerated `series_library.db`, `series_library_data.json`, and `series_library_details.json` when output changes.
4. Run `npm test`.

For long IMDbAPI jobs, prefer background PowerShell jobs with logs under `scripts/.generated`, then poll progress. IMDbAPI can return 429s; existing scripts back off and retry.

## Testing

Always run:

```powershell
npm test
```

The verification checks:

- public JSON matches SQLite totals
- compact public index/detail schema
- category coverage
- Comedy source, filter, and season-refresh coverage
- trend labels and thresholds
- Disaster threshold
- rated-season guards
- rated-season count export and filtering
- API-backed personal tag state
- modal/card UI invariants
- static/Vercel readiness
- local static server readiness
- absence of catalog update UI/API references

For trend work, also verify individual examples with `series_library_data.json` when needed.

## Git Practices

- Do not commit ignored generated logs or cache files.
- Do not commit SQLite sidecars `series_library.db-shm` or `series_library.db-wal`.
- Do not commit local personal state DB files `series_user_state.db*`.
- Do commit the main SQLite DB and public JSON when data changes.
- Do commit `series_library_details.json` with `series_library_data.json` when export output changes.
- Keep commits small and testable.
- Push after approved/finished slices when requested.

## Common Pitfalls

- The script named `build_sci_fi_catalog_page.ps1` is not Sci-Fi-only anymore.
- The test script name is historical; it validates all current categories.
- Comedy is a primary source category; Animation remains a secondary detail-derived filter/tag.
- Pending/unrated seasons must not be treated as `0`.
- Trend eligibility is based on 3+ rated seasons, not total seasons.
- Trend rules live in `scripts/trend_rules.js`; avoid duplicating thresholds in migration/export/frontend code.
- Rated-season count filtering must use exported `ratedSeasonCount`, not total season labels or pending seasons.
- Vercel serves static JSON; changing SQLite alone does not update the public page.
- The public index intentionally excludes modal-only fields; detail modal data belongs in `series_library_details.json`.
- Personal tags must not be exported into `series_library_data.json`; they belong in the series-state API.
- Existing primary source folders include tracked CSV and some older tracked JSON. Do not expand this pattern with new raw JSON unless explicitly requested.
- If local server does not respond on port `3000`, check `8787`; `series_library_server.js` defaults to `127.0.0.1:8787`.
