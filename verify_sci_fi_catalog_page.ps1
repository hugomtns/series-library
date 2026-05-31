$ErrorActionPreference = "Stop"

$html = Get-Content -Path "series_library.html" -Raw
$env:SERIES_LIBRARY_DB = Join-Path (Resolve-Path ".") "series_library.db"
$dataJson = & node -e "const Database = require('better-sqlite3'); const db = new Database(process.env.SERIES_LIBRARY_DB, { readonly: true }); const meta = Object.fromEntries(db.prepare('SELECT key, value FROM metadata').all().map(row => [row.key, row.value])); const rows = db.prepare('SELECT payload_json, imdb_score, vote_count, season_count, season_label, episode_count FROM series ORDER BY start_year ASC, imdb_score DESC, vote_count DESC, title ASC').all(); db.close(); const series = rows.map(row => { const item = JSON.parse(row.payload_json); item.score = row.imdb_score; item.votes = row.vote_count; item.seasons = row.season_count; item.seasonLabel = row.season_label; item.episodes = row.episode_count; return item; }); const yearCounts = new Map(); for (const item of series) yearCounts.set(item.year, (yearCounts.get(item.year) || 0) + 1); process.stdout.write(JSON.stringify({ generatedAt: meta.generatedAt || '', total: series.length, years: Array.from(yearCounts, ([year, count]) => ({ year, count })), series }));"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read catalog from SQLite."
}
$data = $dataJson | ConvertFrom-Json

$series = @($data.series)
$badVotes = @($series | Where-Object { [int]$_.votes -lt 5000 })
$missingPosters = @($series | Where-Object { [string]::IsNullOrWhiteSpace($_.poster) })
$missingSynopsis = @($series | Where-Object { [string]::IsNullOrWhiteSpace($_.synopsis) -or $_.synopsis -eq "No synopsis available." })
$missingSeasons = @($series | Where-Object { [int]$_.seasons -eq 0 })
$badJapanExamples = @($series | Where-Object { $_.title -match "Dragon Ball|Trigun" })
$missingCategories = @($series | Where-Object { -not $_.categories -or @($_.categories).Count -eq 0 })
$turkishPrimaryRows = @($series | Where-Object { $_.primaryOrigin -eq "TR" })
$sciFiRows = @($series | Where-Object { @($_.categories) -contains "Sci-Fi" })
$fantasyRows = @($series | Where-Object { @($_.categories) -contains "Fantasy" })
$bothRows = @($series | Where-Object { @($_.categories) -contains "Sci-Fi" -and @($_.categories) -contains "Fantasy" })
$years = @($data.years)

[pscustomobject]@{
  Total = $data.total
  SeriesRows = $series.Count
  Years = $years.Count
  FirstYear = ($years | Sort-Object { [int]$_.year } | Select-Object -First 1).year
  LastYear = ($years | Sort-Object { [int]$_.year } | Select-Object -Last 1).year
  MissingPosters = $missingPosters.Count
  MissingSynopsis = $missingSynopsis.Count
  MissingSeasons = $missingSeasons.Count
  BadVotes = $badVotes.Count
  DragonBallOrTrigunRows = $badJapanExamples.Count
  SciFiRows = $sciFiRows.Count
  FantasyRows = $fantasyRows.Count
  BothRows = $bothRows.Count
  MissingCategories = $missingCategories.Count
  TurkishPrimaryRows = $turkishPrimaryRows.Count
  HasYearNavigation = $html.Contains('id="yearNav"')
  HasYearSelect = $html.Contains('id="yearSelect"')
  HasCategoryFilter = $html.Contains('id="categoryFilter"')
  HasDecadeGroups = $html.Contains('"decade-group"')
  HasPosterMarkup = $html.Contains('class="poster"')
  HasSearch = $html.Contains('id="search"')
  HasTitleSearchPlaceholder = $html.Contains('placeholder="Search titles..."')
  HasSynopsisMarkup = $html.Contains('class="synopsis"')
  CardSearchIncludesSynopsis = $html.Contains('data-search="${escapeText([item.title, item.synopsis')
  HasSeriesDetailModal = $html.Contains('id="seriesDetailModal"')
  HasSeriesDetailSynopsis = $html.Contains('class="detail-synopsis"')
  HasClickableCards = $html.Contains('role="button"') -and $html.Contains('data-id="${escapeText(item.id)}"')
  HasSeriesDetailFooter = $html.Contains('class="series-detail-foot"')
  HasSeriesDetailDone = $html.Contains('id="seriesDetailDone"')
  HasSeriesDetailImdbLink = $html.Contains('<a class="imdb-link fact"')
} | Format-List

if ($data.total -ne $series.Count) { throw "Catalog total does not match SQLite series rows." }
if ($years.Count -lt 60) { throw "Expected at least 60 years with eligible series after extending to 1960." }
if ((($years | Sort-Object { [int]$_.year } | Select-Object -First 1).year) -gt 1961) { throw "Expected catalog to include early 1960s entries." }
if ($badVotes.Count -gt 0) { throw "Found rows below 5000 votes." }
if ($badJapanExamples.Count -gt 0) { throw "Found excluded Japanese-primary examples." }
if ($missingCategories.Count -gt 0) { throw "Found rows without category metadata." }
if ($turkishPrimaryRows.Count -gt 0) { throw "Found Turkish-primary rows." }
if ($sciFiRows.Count -lt 600) { throw "Expected at least 600 Sci-Fi rows." }
if ($fantasyRows.Count -lt 500) { throw "Expected at least 500 Fantasy rows." }
if ($bothRows.Count -lt 200) { throw "Expected at least 200 rows in both categories." }
if (-not $html.Contains('id="yearNav"')) { throw "Missing year navigation." }
if (-not $html.Contains('id="yearSelect"')) { throw "Missing year select." }
if (-not $html.Contains('id="categoryFilter"')) { throw "Missing category filter." }
if (-not $html.Contains('"decade-group"')) { throw "Missing decade group renderer." }
if (-not $html.Contains('class="poster"')) { throw "Missing poster markup." }
if (-not $html.Contains('id="search"')) { throw "Missing search input." }
if (-not $html.Contains('placeholder="Search titles..."')) { throw "Search input should be title-focused." }
if ($html.Contains('class="synopsis"')) { throw "Cards should not render synopsis markup." }
if ($html.Contains('data-search="${escapeText([item.title, item.synopsis')) { throw "Card search should not include synopsis." }
if (-not $html.Contains('id="seriesDetailModal"')) { throw "Missing series detail modal." }
if (-not $html.Contains('class="detail-synopsis"')) { throw "Detail modal should render synopsis." }
if (-not ($html.Contains('role="button"') -and $html.Contains('data-id="${escapeText(item.id)}"'))) { throw "Series cards should be keyboard-openable detail triggers." }
if ($html.Contains('class="series-detail-foot"')) { throw "Series detail modal should not have a footer action bar." }
if ($html.Contains('id="seriesDetailDone"')) { throw "Series detail modal should only use the close button." }
if ($html.Contains('<a class="imdb-link fact"')) { throw "Series detail modal should not duplicate the IMDb link." }
