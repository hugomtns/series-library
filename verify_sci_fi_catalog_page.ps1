$ErrorActionPreference = "Stop"

$html = Get-Content -Path "series_library.html" -Raw
$css = Get-Content -Path "series_library.css" -Raw
$publicData = Get-Content -Path "series_library_data.json" -Raw | ConvertFrom-Json
$vercelConfig = Get-Content -Path "vercel.json" -Raw
$env:SERIES_LIBRARY_DB = Join-Path (Resolve-Path ".") "series_library.db"
$dataJson = & node -e "const Database = require('better-sqlite3'); const db = new Database(process.env.SERIES_LIBRARY_DB, { readonly: true }); const meta = Object.fromEntries(db.prepare('SELECT key, value FROM metadata').all().map(row => [row.key, row.value])); const seasonRows = db.prepare('SELECT imdb_id, season_number, label, episode_count, start_year, end_year, imdb_score, vote_count FROM series_seasons ORDER BY imdb_id ASC, season_number ASC').all(); const seasonsBySeries = new Map(); for (const row of seasonRows) { if (!seasonsBySeries.has(row.imdb_id)) seasonsBySeries.set(row.imdb_id, []); seasonsBySeries.get(row.imdb_id).push({ season: row.season_number, label: row.label, episodeCount: row.episode_count, startYear: row.start_year, endYear: row.end_year, score: row.imdb_score, votes: row.vote_count }); } const rows = db.prepare('SELECT payload_json, imdb_score, vote_count, season_count, season_label, episode_count, season_rating_trend_slope, season_rating_trend_intercept, season_rating_trend_points FROM series ORDER BY start_year ASC, imdb_score DESC, vote_count DESC, title ASC').all(); db.close(); const series = rows.map(row => { const item = JSON.parse(row.payload_json); item.score = row.imdb_score; item.votes = row.vote_count; item.seasons = row.season_count; item.seasonLabel = row.season_label; item.episodes = row.episode_count; item.seasonTrend = { slope: row.season_rating_trend_slope, intercept: row.season_rating_trend_intercept, points: row.season_rating_trend_points }; item.seasonDetails = seasonsBySeries.get(item.id) || []; return item; }); const yearCounts = new Map(); for (const item of series) yearCounts.set(item.year, (yearCounts.get(item.year) || 0) + 1); process.stdout.write(JSON.stringify({ generatedAt: meta.generatedAt || '', total: series.length, seasonRows: seasonRows.length, years: Array.from(yearCounts, ([year, count]) => ({ year, count })), series }));"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read catalog from SQLite."
}
$data = $dataJson | ConvertFrom-Json

$series = @($data.series)
$badVotes = @($series | Where-Object { [int]$_.votes -lt 5000 })
$missingPosters = @($series | Where-Object { [string]::IsNullOrWhiteSpace($_.poster) })
$missingSynopsis = @($series | Where-Object { [string]::IsNullOrWhiteSpace($_.synopsis) -or $_.synopsis -eq "No synopsis available." })
$missingSeasons = @($series | Where-Object { [int]$_.seasons -eq 0 })
$seriesWithSeasonDetails = @($series | Where-Object { @($_.seasonDetails).Count -gt 0 })
$trendEligibleRows = @($series | Where-Object { [int]$_.seasons -ge 3 })
$trendCalculatedRows = @($trendEligibleRows | Where-Object { $null -ne $_.seasonTrend.slope })
$disasterRows = @()
foreach ($item in $series) {
  $seasons = @($item.seasonDetails | Sort-Object { [int]$_.season })
  if ([int]$item.seasons -ge 3 -and $seasons.Count -ge 2 -and $null -ne $seasons[0].score -and $null -ne $seasons[-1].score) {
    $delta = [double]$seasons[-1].score - [double]$seasons[0].score
    if ($delta -le -1.5) {
      $disasterRows += $item
    }
  }
}
$seasonDetailRows = @($series | ForEach-Object { @($_.seasonDetails) })
$badSeasonDetailRows = @($seasonDetailRows | Where-Object { [int]$_.season -lt 0 -or [int]$_.episodeCount -lt 0 })
$badJapanExamples = @($series | Where-Object { $_.title -match "Dragon Ball|Trigun" })
$missingCategories = @($series | Where-Object { -not $_.categories -or @($_.categories).Count -eq 0 })
$turkishPrimaryRows = @($series | Where-Object { $_.primaryOrigin -eq "TR" })
$sciFiRows = @($series | Where-Object { @($_.categories) -contains "Sci-Fi" })
$fantasyRows = @($series | Where-Object { @($_.categories) -contains "Fantasy" })
$actionRows = @($series | Where-Object { @($_.categories) -contains "Action" })
$bothRows = @($series | Where-Object { @($_.categories) -contains "Sci-Fi" -and @($_.categories) -contains "Fantasy" })
$years = @($data.years)

[pscustomobject]@{
  Total = $data.total
  PublicDataTotal = $publicData.total
  SeriesRows = $series.Count
  Years = $years.Count
  FirstYear = ($years | Sort-Object { [int]$_.year } | Select-Object -First 1).year
  LastYear = ($years | Sort-Object { [int]$_.year } | Select-Object -Last 1).year
  MissingPosters = $missingPosters.Count
  MissingSynopsis = $missingSynopsis.Count
  MissingSeasons = $missingSeasons.Count
  SeriesWithSeasonDetails = $seriesWithSeasonDetails.Count
  TrendEligibleRows = $trendEligibleRows.Count
  TrendCalculatedRows = $trendCalculatedRows.Count
  DisasterRows = $disasterRows.Count
  SeasonDetailRows = $seasonDetailRows.Count
  BadSeasonDetailRows = $badSeasonDetailRows.Count
  BadVotes = $badVotes.Count
  DragonBallOrTrigunRows = $badJapanExamples.Count
  SciFiRows = $sciFiRows.Count
  FantasyRows = $fantasyRows.Count
  ActionRows = $actionRows.Count
  BothRows = $bothRows.Count
  MissingCategories = $missingCategories.Count
  TurkishPrimaryRows = $turkishPrimaryRows.Count
  HasYearNavigation = $html.Contains('id="yearNav"')
  HasStylesheet = $html.Contains('href="series_library.css"')
  HasInlineStyleBlock = $html.Contains('<style>')
  HasExtractedCss = $css.Contains('.card') -and $css.Contains('.series-detail-modal')
  UsesStaticCatalogJson = $html.Contains('fetch("series_library_data.json"')
  HasUpdateButton = $html.Contains('id="updateButton"')
  HasUpdateApiReference = $html.Contains('/api/update') -or $html.Contains('EventSource')
  HasVercelRootRewrite = $vercelConfig.Contains('"source": "/"') -and $vercelConfig.Contains('"destination": "/series_library.html"')
  HasYearSelect = $html.Contains('id="yearSelect"')
  HasCategoryFilter = $html.Contains('id="categoryFilter"')
  HasActionCategoryFilter = $html.Contains('class="category-choice" value="Action"')
  HasTrendFilter = $html.Contains('id="trendFilter"')
  HasActionSourceConfig = (Get-Content -Path "build_combined_genre_catalog_source.ps1" -Raw).Contains('imdb_action_year_files_primary_origin') -and (Get-Content -Path "scripts/update_current_year_sources.ps1" -Raw).Contains('Genre = "Action"')
  HasTrendFilterChoices = $html.Contains('class="trend-choice"') -and $html.Contains('value="up"') -and $html.Contains('value="down"') -and $html.Contains('value="disaster"')
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
  HasSeriesDetailLayout = $html.Contains('class="detail-layout"')
  HasSeriesDetailInfo = $html.Contains('class="detail-info"')
  HasDetailDuplicateTags = $html.Contains('class="detail-tags"')
  HasSeasonDetailTable = $html.Contains('class="season-table"')
  HasSeasonPendingState = $html.Contains('Pending')
  HasTrendTag = $html.Contains('class="trend-tag')
  HasTrendUp = $html.Contains('Trend Up')
  HasTrendDown = $html.Contains('Trend Down')
  HasDisaster = $html.Contains('Disaster')
  HasCardTrendDataset = $html.Contains('data-trend="${escapeText(trendKind(item) || "")}"')
  HasSoftTrendUpThreshold = $html.Contains('slope >= 0.3')
  HasSoftTrendDownThreshold = $html.Contains('slope <= -0.3')
  HasFiniteSeasonScoreGuard = $html.Contains('function finiteSeasonScore')
  HasUnsafeSeasonScoreNumberCast = $html.Contains('y: Number(season.score)')
  HasDisasterThreshold = $html.Contains('lastScore - firstScore <= -1.5')
} | Format-List

if ($data.total -ne $series.Count) { throw "Catalog total does not match SQLite series rows." }
if ($publicData.total -ne $data.total) { throw "Public JSON total does not match SQLite catalog total." }
if ($years.Count -lt 60) { throw "Expected at least 60 years with eligible series after extending to 1960." }
if ((($years | Sort-Object { [int]$_.year } | Select-Object -First 1).year) -gt 1961) { throw "Expected catalog to include early 1960s entries." }
if ($badVotes.Count -gt 0) { throw "Found rows below 5000 votes." }
if ($badJapanExamples.Count -gt 0) { throw "Found excluded Japanese-primary examples." }
if ($missingCategories.Count -gt 0) { throw "Found rows without category metadata." }
if ($seriesWithSeasonDetails.Count -lt 1000) { throw "Expected most series to include normalized season detail rows." }
if ($trendEligibleRows.Count -lt 500) { throw "Expected many series to be eligible for season rating trends." }
if ($trendCalculatedRows.Count -lt 450) { throw "Expected most eligible series with rated seasons to have trend slopes." }
if ($disasterRows.Count -lt 10) { throw "Expected several series to match the Disaster first-vs-last-season drop." }
if ($seasonDetailRows.Count -lt $series.Count) { throw "Expected at least one season detail row per series on average." }
if ($badSeasonDetailRows.Count -gt 0) { throw "Found invalid normalized season detail rows." }
if ($turkishPrimaryRows.Count -gt 0) { throw "Found Turkish-primary rows." }
if ($sciFiRows.Count -lt 600) { throw "Expected at least 600 Sci-Fi rows." }
if ($fantasyRows.Count -lt 500) { throw "Expected at least 500 Fantasy rows." }
if ($bothRows.Count -lt 200) { throw "Expected at least 200 rows in both categories." }
if (-not $html.Contains('class="category-choice" value="Action"')) { throw "Missing Action category filter." }
if (-not ((Get-Content -Path "build_combined_genre_catalog_source.ps1" -Raw).Contains('imdb_action_year_files_primary_origin') -and (Get-Content -Path "scripts/update_current_year_sources.ps1" -Raw).Contains('Genre = "Action"'))) { throw "Missing Action source configuration." }
if (-not $html.Contains('href="series_library.css"')) { throw "Missing extracted stylesheet link." }
if ($html.Contains('<style>')) { throw "HTML should not contain an inline style block." }
if (-not ($css.Contains('.card') -and $css.Contains('.series-detail-modal'))) { throw "Extracted stylesheet is missing expected UI styles." }
if (-not $html.Contains('fetch("series_library_data.json"')) { throw "Public page should load static catalog JSON." }
if ($html.Contains('id="updateButton"')) { throw "Public page should not expose update controls." }
if ($html.Contains('/api/update') -or $html.Contains('EventSource')) { throw "Public page should not reference update APIs." }
if (-not ($vercelConfig.Contains('"source": "/"') -and $vercelConfig.Contains('"destination": "/series_library.html"'))) { throw "Missing Vercel root rewrite." }
if (-not $html.Contains('id="yearNav"')) { throw "Missing year navigation." }
if (-not $html.Contains('id="yearSelect"')) { throw "Missing year select." }
if (-not $html.Contains('id="categoryFilter"')) { throw "Missing category filter." }
if (-not $html.Contains('id="trendFilter"')) { throw "Missing trend filter." }
if (-not ($html.Contains('class="trend-choice"') -and $html.Contains('value="up"') -and $html.Contains('value="down"') -and $html.Contains('value="disaster"'))) { throw "Missing trend filter choices." }
if (-not $html.Contains('"decade-group"')) { throw "Missing decade group renderer." }
if (-not $html.Contains('class="poster"')) { throw "Missing poster markup." }
if (-not $html.Contains('id="search"')) { throw "Missing search input." }
if (-not $html.Contains('placeholder="Search titles..."')) { throw "Search input should be title-focused." }
if ($html.Contains('class="synopsis"')) { throw "Cards should not render synopsis markup." }
if ($html.Contains('data-search="${escapeText([item.title, item.synopsis')) { throw "Card search should not include synopsis." }
if (-not $html.Contains('id="seriesDetailModal"')) { throw "Missing series detail modal." }
if (-not $html.Contains('class="detail-layout"')) { throw "Detail modal should use the poster/info/synopsis/season layout." }
if (-not $html.Contains('class="detail-info"')) { throw "Detail modal should render card-style series info." }
if (-not $html.Contains('class="detail-synopsis"')) { throw "Detail modal should render synopsis." }
if ($html.Contains('class="detail-tags"')) { throw "Detail modal should not render a duplicate genre/tag row." }
if ($html.Contains('class="detail-fact"')) { throw "Detail modal should not restate card facts as separate metric boxes." }
if (-not ($html.Contains('role="button"') -and $html.Contains('data-id="${escapeText(item.id)}"'))) { throw "Series cards should be keyboard-openable detail triggers." }
if ($html.Contains('class="series-detail-foot"')) { throw "Series detail modal should not have a footer action bar." }
if ($html.Contains('id="seriesDetailDone"')) { throw "Series detail modal should only use the close button." }
if ($html.Contains('<a class="imdb-link fact"')) { throw "Series detail modal should not duplicate the IMDb link." }
if (-not $html.Contains('class="season-table"')) { throw "Series detail modal should render season details." }
if (-not $html.Contains('<span>Year</span>')) { throw "Series detail modal should render season years." }
if (-not $html.Contains('class="season-score"')) { throw "Rated seasons should render as score pills." }
if (-not $html.Contains('Pending')) { throw "Season ratings should show a pending state when rating data is unavailable." }
if (-not $html.Contains('class="trend-tag')) { throw "Series cards should render trend tags." }
if (-not $html.Contains('Trend Up')) { throw "Series cards should support Trend Up tags." }
if (-not $html.Contains('Trend Down')) { throw "Series cards should support Trend Down tags." }
if (-not $html.Contains('Disaster')) { throw "Series cards should support Disaster tags." }
if (-not $html.Contains('data-trend="${escapeText(trendKind(item) || "")}"')) { throw "Series cards should expose trend data for filtering." }
if (-not $html.Contains('slope >= 0.3')) { throw "Trend Up should use the softened 0.3 threshold." }
if (-not $html.Contains('slope <= -0.3')) { throw "Trend Down should use the softened -0.3 threshold." }
if (-not $html.Contains('function finiteSeasonScore')) { throw "Trend calculations should guard against pending null season scores." }
if ($html.Contains('y: Number(season.score)')) { throw "Trend fallback should not cast pending null season scores to zero." }
if (-not $html.Contains('lastScore - firstScore <= -1.5')) { throw "Disaster should use the 1.5 point drop threshold." }
