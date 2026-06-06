# Series Library Design Context

## Design Register

Product UI for a static catalog browser.

## Visual Strategy

Use a restrained dark product palette: tinted neutrals, one electric cyan/teal accent for selected/current/action states, and semantic colors only where they carry meaning.

The app is a quiet but distinctive browsing tool, not a branded media site. The design should support scanning thousands of poster-led records, comparing ratings, and opening details repeatedly.

The current visual direction is Orbital Catalog: dark, minimal, poster-forward, dense, and technical without decorative sci-fi effects.

## Tokens

- Font: system UI for body and controls; system-native condensed display stack for headings and series titles (`Bahnschrift`, `Aptos Display`, `Arial Narrow`, then system UI fallback). Do not add remote font dependencies unless explicitly requested.
- Corners: 8px for controls, cards, and panels; larger radii only for circular icon buttons and pills.
- Surfaces: dark cool-tinted background, raised control rail, subtle borders.
- Accent: cyan/teal family for selected navigation, focused controls, and primary text actions.
- Focus: visible cyan focus ring shared across controls.
- Shadows: use sparingly, mainly for dropdown menus, the modal, and the floating back-to-list control.
- Avoid paint-heavy decoration on repeated cards: no backdrop blur, no per-card overlay pseudo-elements, no heavy repeated shadows.

## Component Vocabulary

- Filter triggers, selects, search, score/rated-season inputs, and reset buttons must share the same control system: height, border, radius, fill, focus, and hover treatment.
- Cards are repeated catalog items only. Desktop cards are poster-wall tiles with stable dimensions; mobile cards may become compact media rows. Do not wrap page sections in decorative cards.
- Detail modal uses a large poster, compact metadata section, synopsis, and season table loaded from the static detail payload. Desktop should use the width efficiently with poster on one side and information/seasons on the other. No footer action bar.
- Personal tag toggles live in the detail modal as compact state buttons. Active personal tags render as small semantic pills on both cards and the modal.
- Back-to-list control is a small fixed button that appears only after scrolling into the catalog and scrolls to the top of the series list.
- Trend tags are semantic pills:
  - `up`: positive green.
  - `down`: warning red.
  - `disaster`: high-contrast severe red.
- Personal tags are semantic pills:
  - `wishlisted`: cyan/teal.
  - `available`: green.
  - `seen`: muted violet/blue.
- Rating pills use score-derived color and must remain legible.

## Layout

- Desktop uses a sticky left sidebar, sticky search/status toolbar, and poster-wall catalog grid.
- Mobile collapses filters behind a `details` panel.
- Catalog cards need stable poster and metadata dimensions to avoid layout shift or clipped labels.
- Long titles and labels must wrap without overlapping controls.
- Detail modal must lock background scroll and avoid scroll jumps on close.

## Interaction

- Cards open with click, Enter, or Space.
- Modal traps focus while open and closes with Escape or the close button.
- Filter menus close on Escape and outside click.
- Back-to-list button scrolls to `#catalog`, respects reduced motion, and hides again near the list top.
- Filter result counts and status changes should be announced politely.
- Motion should be short, state-driven, and respect `prefers-reduced-motion`.

## Content Style

- Keep labels terse and operational.
- Use title-focused search language.
- Avoid explanatory in-app text that describes obvious UI behavior.
- Preserve exact category and trend terms used by the data model.
