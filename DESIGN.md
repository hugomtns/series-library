# Series Library Design Context

## Design Register

Product UI for a static catalog browser.

## Visual Strategy

Use a restrained product palette: tinted neutrals, one warm accent for selected/current states, and semantic colors only where they carry meaning.

The app is a quiet browsing tool, not a branded media site. The design should support scanning hundreds of rows, comparing ratings, and opening details repeatedly.

## Tokens

- Font: system UI stack only.
- Corners: 8px for controls, cards, and panels; larger radii only for circular icon buttons and pills.
- Surfaces: cool tinted background, lighter panels, subtle borders.
- Accent: warm orange/brown family for selected navigation and primary text actions.
- Focus: visible blue focus ring shared across controls.
- Shadows: use sparingly, mainly for dropdown menus and modals.

## Component Vocabulary

- Filter triggers, selects, search, score inputs, and reset buttons must share the same control system: height, border, radius, fill, focus, and hover treatment.
- Cards are repeated catalog items only. Do not wrap page sections in decorative cards.
- Detail modal uses a poster, compact metadata section, synopsis, and season table. No footer action bar.
- Trend tags are semantic pills:
  - `up`: positive green.
  - `down`: warning red.
  - `disaster`: high-contrast severe red.
- Rating pills use score-derived color and must remain legible.

## Layout

- Desktop uses a sticky left sidebar and main catalog grid.
- Mobile collapses filters behind a `details` panel.
- Catalog cards need stable poster dimensions to avoid layout shift.
- Long titles and labels must wrap without overlapping controls.
- Detail modal must lock background scroll and avoid scroll jumps on close.

## Interaction

- Cards open with click, Enter, or Space.
- Modal traps focus while open and closes with Escape or the close button.
- Filter menus close on Escape and outside click.
- Filter result counts and status changes should be announced politely.
- Motion should be short, state-driven, and respect `prefers-reduced-motion`.

## Content Style

- Keep labels terse and operational.
- Use title-focused search language.
- Avoid explanatory in-app text that describes obvious UI behavior.
- Preserve exact category and trend terms used by the data model.
