# Public Data Schema

The browser reads only committed static JSON files. SQLite remains the source of truth, and `scripts/export_public_catalog.js` is the only public JSON exporter.

## `series_library_data.json`

Top-level fields:

- `generatedAt`: export timestamp from SQLite metadata.
- `total`: number of public series rows.
- `years`: ordered year summary objects with `year` and `count`.
- `series`: ordered public index rows, sorted by year ascending, then score, votes, and title.

Public index row fields:

- `id`: IMDb title id. The client derives IMDb links from this value.
- `title`: display title.
- `year`: numeric start year.
- `years`: IMDb year span text.
- `score`: IMDb title score.
- `poster`: poster image URL.
- `seasonLabel`: compact season count label.
- `primaryOrigin`: primary origin country code.
- `categories`: display/filter categories. `Animation` is secondary and can appear alongside source categories.
- `trendSlope`: season rating regression slope, omitted when null.
- `trendKind`: one of `up`, `down`, or `disaster`, omitted when no label applies.

The public index must not include modal-only or unused fields such as `synopsis`, `seasonDetails`, `imdbUrl`, `votes`, `rank`, `type`, `seasons`, `episodes`, `genres`, `countries`, `countryCodes`, `posterWidth`, `posterHeight`, or `seasonTrend`.

## `series_library_details.json`

Top-level fields:

- `generatedAt`: export timestamp from SQLite metadata.
- `total`: number of detail rows. Must match `series_library_data.json.total`.
- `series`: object keyed by IMDb title id.

Detail row fields:

- `synopsis`: detail modal synopsis text.
- `seasonDetails`: ordered season rows for the modal.

Season detail row fields:

- `season`: numeric season number.
- `episodeCount`: episode count, omitted when null.
- `startYear`: season start year, omitted when null.
- `endYear`: season end year, omitted when null.
- `score`: season IMDb average, omitted when null or pending.

Detail rows do not repeat `id`. Season detail rows must not include `label` or `votes`.

## Null Handling

Public exports omit null and undefined values recursively. Consumers should treat missing optional fields as unavailable rather than as zero.

## Trend Fields

Trend semantics live in `scripts/trend_rules.js`:

- Use rated seasons only.
- Require at least three rated seasons.
- `disaster`: last rated season is at least 1.5 IMDb points below the first rated season.
- `up`: regression slope is at least `0.3`.
- `down`: regression slope is at most `-0.3`.
- `disaster` supersedes `down`.
