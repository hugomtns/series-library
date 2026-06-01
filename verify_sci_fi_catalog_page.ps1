$ErrorActionPreference = "Stop"

$html = Get-Content -Path "series_library.html" -Raw
$css = Get-Content -Path "series_library.css" -Raw
$clientJs = if (Test-Path -Path "series_library.js") { Get-Content -Path "series_library.js" -Raw } else { "" }
$pageSource = "$html`n$clientJs"
$packageJson = Get-Content -Path "package.json" -Raw
$catalogBuilder = Get-Content -Path "build_sci_fi_catalog_page.ps1" -Raw
$seasonRefreshScript = Get-Content -Path "scripts/refresh_open_series_seasons.ps1" -Raw
$updateScript = Get-Content -Path "scripts/update_library.js" -Raw
$verifyScript = Get-Content -Path "verify_sci_fi_catalog_page.ps1" -Raw
$publicData = Get-Content -Path "series_library_data.json" -Raw | ConvertFrom-Json
$publicDetails = if (Test-Path -Path "series_library_details.json") { Get-Content -Path "series_library_details.json" -Raw | ConvertFrom-Json } else { $null }
$vercelConfig = Get-Content -Path "vercel.json" -Raw
$env:SERIES_LIBRARY_DB = Join-Path (Resolve-Path ".") "series_library.db"
$dataJson = & node "scripts/read_catalog_for_verify.js"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read catalog from SQLite."
}
$data = $dataJson | ConvertFrom-Json

$series = @($data.series)
$publicSeries = @($publicData.series)
$publicDetailSeries = if ($null -ne $publicDetails) { @($publicDetails.series) } else { @() }
$publicIndexRowsWithDetails = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "synopsis" -or $_.PSObject.Properties.Name -contains "seasonDetails" })
$publicIndexRowsWithTrendPayload = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "seasonTrend" })
$publicIndexRowsWithImdbUrl = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "imdbUrl" })
$publicIndexRowsWithPosterDimensions = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "posterWidth" -or $_.PSObject.Properties.Name -contains "posterHeight" })
$publicDetailRowsWithDetails = @($publicDetailSeries | Where-Object { $_.PSObject.Properties.Name -contains "synopsis" -and $_.PSObject.Properties.Name -contains "seasonDetails" })
$badVotes = @($series | Where-Object { [int]$_.votes -lt 5000 })
$missingPosters = @($series | Where-Object { [string]::IsNullOrWhiteSpace($_.poster) })
$missingSynopsis = @($series | Where-Object { [string]::IsNullOrWhiteSpace($_.synopsis) -or $_.synopsis -eq "No synopsis available." })
$missingSeasons = @($series | Where-Object { [int]$_.seasons -eq 0 })
$seriesWithSeasonDetails = @($series | Where-Object { @($_.seasonDetails).Count -gt 0 })
$trendEligibleRows = @($series | Where-Object { @($_.seasonDetails | Where-Object { $null -ne $_.score }).Count -ge 3 })
$trendCalculatedRows = @($trendEligibleRows | Where-Object { $null -ne $_.seasonTrend.slope })
$disasterRows = @()
foreach ($item in $series) {
  $seasons = @($item.seasonDetails | Where-Object { $null -ne $_.score } | Sort-Object { [int]$_.season })
  if ($seasons.Count -ge 3) {
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
  PublicDetailsTotal = if ($null -ne $publicDetails) { $publicDetails.total } else { 0 }
  PublicIndexRowsWithDetails = $publicIndexRowsWithDetails.Count
  PublicIndexRowsWithTrendPayload = $publicIndexRowsWithTrendPayload.Count
  PublicIndexRowsWithImdbUrl = $publicIndexRowsWithImdbUrl.Count
  PublicIndexRowsWithPosterDimensions = $publicIndexRowsWithPosterDimensions.Count
  PublicDetailRowsWithDetails = $publicDetailRowsWithDetails.Count
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
  HasExternalClientScript = $html.Contains('<script type="module" src="series_library.js"></script>') -and $clientJs.Contains('async function loadCatalogData')
  HasInlineModuleScript = $html.Contains('<script type="module">')
  HasDeadYearNavigationCode = $clientJs.Contains('for (const yearInfo of data.years)')
  HasInlineNodeVerificationReader = $verifyScript.Contains('node ' + '-e')
  HasInlineStyleBlock = $html.Contains('<style>')
  HasCatalogBuilderHtmlOutput = $catalogBuilder.Contains('$OutHtml') -or $catalogBuilder.Contains('$SkipHtml') -or $catalogBuilder.Contains('$html = @''') -or $catalogBuilder.Contains('<style>')
  HasExtractedCss = $css.Contains('.card') -and $css.Contains('.series-detail-modal')
  HasYearSectionRenderContainment = $css.Contains('content-visibility: auto') -and $css.Contains('contain-intrinsic-size')
  HasIncrementalCatalogRender = $pageSource.Contains('requestIdleCallback') -and $pageSource.Contains('function ensureCatalogRendered')
  HasTouchSizedControls = -not ($css.Contains('min-height: 38px') -or $css.Contains('min-height: 36px') -or $css.Contains('min-height: 34px') -or $css.Contains('width: 34px') -or $css.Contains('height: 34px'))
  UsesStaticCatalogJson = $pageSource.Contains('fetch("series_library_data.json"')
  UsesLazySeriesDetailsJson = $pageSource.Contains('fetch("series_library_details.json"')
  HasUpdateButton = $html.Contains('id="updateButton"')
  HasUpdateApiReference = $pageSource.Contains('/api/update') -or $pageSource.Contains('EventSource')
  HasVercelRootRewrite = $vercelConfig.Contains('"source": "/"') -and $vercelConfig.Contains('"destination": "/series_library.html"')
  HasYearSelect = $html.Contains('id="yearSelect"')
  HasCategoryFilter = $html.Contains('id="categoryFilter"')
  HasMobileFilterPanel = $html.Contains('id="filterPanel"') -and $css.Contains('.filter-summary') -and $pageSource.Contains('mobileFilterQuery')
  HasActionCategoryFilter = $html.Contains('class="category-choice" value="Action"')
  HasActionSeasonRefresh = $packageJson.Contains('refresh:action-seasons') -and (Get-Content -Path "scripts/refresh_open_series_seasons.ps1" -Raw).Contains('REFRESH_CATEGORY')
  HasCachedSeasonRefreshDefault = $updateScript.Contains('refresh_open_series_seasons.ps1') -and $updateScript.Contains('"-SkipExisting"')
  HasParallelSeasonRefresh = $seasonRefreshScript.Contains('[int]$Concurrency') -and $seasonRefreshScript.Contains('Start-Job') -and $updateScript.Contains('"-Concurrency", "2"')
  HasTrendFilter = $html.Contains('id="trendFilter"')
  HasActionSourceConfig = (Get-Content -Path "build_combined_genre_catalog_source.ps1" -Raw).Contains('imdb_action_year_files_primary_origin') -and (Get-Content -Path "scripts/update_current_year_sources.ps1" -Raw).Contains('Genre = "Action"')
  HasTrendFilterChoices = $html.Contains('class="trend-choice"') -and $html.Contains('value="up"') -and $html.Contains('value="down"') -and $html.Contains('value="disaster"')
  HasDecadeGroups = $pageSource.Contains('"decade-group"')
  HasPosterMarkup = $pageSource.Contains('class="poster"')
  HasSearch = $html.Contains('id="search"')
  HasTitleSearchPlaceholder = $html.Contains('placeholder="Search titles..."')
  HasSynopsisMarkup = $pageSource.Contains('class="synopsis"')
  CardSearchIncludesSynopsis = $pageSource.Contains('data-search="${escapeText([item.title, item.synopsis')
  HasSeriesDetailModal = $html.Contains('id="seriesDetailModal"')
  HasSeriesDetailSynopsis = $pageSource.Contains('class="detail-synopsis"')
  HasClickableCards = $pageSource.Contains('role="button"') -and $pageSource.Contains('data-id="${escapeText(item.id)}"')
  HasCardSpaceActivation = $pageSource.Contains('event.key !== "Enter" && event.key !== " "')
  HasModalFocusTrap = $pageSource.Contains('function trapModalFocus') -and $pageSource.Contains('focusableSelectors')
  HasSeriesDetailFooter = $pageSource.Contains('class="series-detail-foot"')
  HasSeriesDetailDone = $pageSource.Contains('id="seriesDetailDone"')
  HasSeriesDetailImdbLink = $pageSource.Contains('<a class="imdb-link fact"')
  HasSeriesDetailLayout = $pageSource.Contains('class="detail-layout"')
  HasSeriesDetailInfo = $pageSource.Contains('class="detail-info"')
  HasDetailDuplicateTags = $pageSource.Contains('class="detail-tags"')
  HasSeasonDetailTable = $pageSource.Contains('class="season-table"')
  HasSeasonPendingState = $pageSource.Contains('Pending')
  HasTrendTag = $pageSource.Contains('class="trend-tag')
  HasTrendUp = $pageSource.Contains('Trend Up')
  HasTrendDown = $pageSource.Contains('Trend Down')
  HasDisaster = $pageSource.Contains('Disaster')
  HasCardTrendDataset = $pageSource.Contains('data-trend="${escapeText(trendKind(item) || "")}"')
  HasDerivedImdbUrl = $pageSource.Contains('function imdbTitleUrl') -and $pageSource.Contains('href="${escapeText(imdbTitleUrl(item))}"')
  HasFilterDataAttributes = $pageSource.Contains('data-score="${escapeText(Number(item.score).toFixed(1))}"') -and $pageSource.Contains('data-primary-categories=')
  HasBatchedFilterInputs = $pageSource.Contains('function scheduleApplyFilters') -and $pageSource.Contains('requestAnimationFrame')
  HasSoftTrendUpThreshold = $pageSource.Contains('slope >= 0.3')
  HasSoftTrendDownThreshold = $pageSource.Contains('slope <= -0.3')
  HasFiniteSeasonScoreGuard = $pageSource.Contains('function finiteSeasonScore')
  HasRatedSeasonPoints = $pageSource.Contains('function ratedSeasonPoints')
  HasUnsafeSeasonScoreNumberCast = $pageSource.Contains('y: Number(season.score)')
  HasDisasterThreshold = $pageSource.Contains('lastScore - firstScore <= -1.5')
} | Format-List

if ($data.total -ne $series.Count) { throw "Catalog total does not match SQLite series rows." }
if ($publicData.total -ne $data.total) { throw "Public JSON total does not match SQLite catalog total." }
if ($null -eq $publicDetails -or $publicDetails.total -ne $data.total) { throw "Public detail JSON total does not match SQLite catalog total." }
if ($publicIndexRowsWithDetails.Count -gt 0) { throw "Public index JSON should not include modal-only synopsis or season detail payloads." }
if ($publicIndexRowsWithTrendPayload.Count -gt 0) { throw "Public index JSON should expose compact trend fields instead of the full seasonTrend payload." }
if ($publicIndexRowsWithImdbUrl.Count -gt 0) { throw "Public index JSON should derive IMDb links from title ids instead of storing imdbUrl per row." }
if ($publicIndexRowsWithPosterDimensions.Count -gt 0) { throw "Public index JSON should not include unused poster dimension fields." }
if ($publicDetailRowsWithDetails.Count -ne $data.total) { throw "Public detail JSON should include one detail payload per series." }
if ($years.Count -lt 60) { throw "Expected at least 60 years with eligible series after extending to 1960." }
if ((($years | Sort-Object { [int]$_.year } | Select-Object -First 1).year) -gt 1961) { throw "Expected catalog to include early 1960s entries." }
if ($badVotes.Count -gt 0) { throw "Found rows below 5000 votes." }
if ($badJapanExamples.Count -gt 0) { throw "Found excluded Japanese-primary examples." }
if ($missingCategories.Count -gt 0) { throw "Found rows without category metadata." }
if ($seriesWithSeasonDetails.Count -lt 1000) { throw "Expected most series to include normalized season detail rows." }
if ($trendEligibleRows.Count -lt 500) { throw "Expected many series to have at least 3 rated seasons for rating trends." }
if ($trendCalculatedRows.Count -lt 450) { throw "Expected most eligible series with rated seasons to have trend slopes." }
if ($disasterRows.Count -lt 10) { throw "Expected several series to match the Disaster first-vs-last-season drop." }
if (-not (@($series | Where-Object { $_.title -eq "The Witcher" -and $_.year -eq 2019 -and @($_.seasonDetails | Where-Object { $null -ne $_.score }).Count -ge 3 }))) { throw "Expected The Witcher to have at least 3 rated seasons." }
if ($seasonDetailRows.Count -lt $series.Count) { throw "Expected at least one season detail row per series on average." }
if ($badSeasonDetailRows.Count -gt 0) { throw "Found invalid normalized season detail rows." }
if ($turkishPrimaryRows.Count -gt 0) { throw "Found Turkish-primary rows." }
if ($sciFiRows.Count -lt 600) { throw "Expected at least 600 Sci-Fi rows." }
if ($fantasyRows.Count -lt 500) { throw "Expected at least 500 Fantasy rows." }
if ($bothRows.Count -lt 200) { throw "Expected at least 200 rows in both categories." }
if (-not $html.Contains('class="category-choice" value="Action"')) { throw "Missing Action category filter." }
if (-not ($packageJson.Contains('refresh:action-seasons') -and (Get-Content -Path "scripts/refresh_open_series_seasons.ps1" -Raw).Contains('REFRESH_CATEGORY'))) { throw "Missing Action season refresh command." }
if (-not ($updateScript.Contains('refresh_open_series_seasons.ps1') -and $updateScript.Contains('"-SkipExisting"'))) { throw "Full update should skip complete season caches by default." }
if (-not ($seasonRefreshScript.Contains('[int]$Concurrency') -and $seasonRefreshScript.Contains('Start-Job') -and $updateScript.Contains('"-Concurrency", "2"'))) { throw "Season refresh should support bounded parallelism for full updates." }
if (-not ((Get-Content -Path "build_combined_genre_catalog_source.ps1" -Raw).Contains('imdb_action_year_files_primary_origin') -and (Get-Content -Path "scripts/update_current_year_sources.ps1" -Raw).Contains('Genre = "Action"'))) { throw "Missing Action source configuration." }
if (-not $html.Contains('href="series_library.css"')) { throw "Missing extracted stylesheet link." }
if (-not ($html.Contains('<script type="module" src="series_library.js"></script>') -and $clientJs.Contains('async function loadCatalogData'))) { throw "Public page should load extracted client JavaScript." }
if ($html.Contains('<script type="module">')) { throw "HTML should not contain the inline app module." }
if ($clientJs.Contains('for (const yearInfo of data.years)')) { throw "Client script should not keep dead year navigation code." }
if ($verifyScript.Contains('node ' + '-e')) { throw "Verification should use a checked-in Node helper instead of inline JavaScript." }
if ($html.Contains('<style>')) { throw "HTML should not contain an inline style block." }
if ($catalogBuilder.Contains('$OutHtml') -or $catalogBuilder.Contains('$SkipHtml') -or $catalogBuilder.Contains('$html = @''') -or $catalogBuilder.Contains('<style>')) { throw "Catalog builder should not contain dead HTML generation code." }
if (-not ($css.Contains('.card') -and $css.Contains('.series-detail-modal'))) { throw "Extracted stylesheet is missing expected UI styles." }
if (-not ($css.Contains('content-visibility: auto') -and $css.Contains('contain-intrinsic-size'))) { throw "Year sections should use render containment for offscreen catalog performance." }
if (-not ($pageSource.Contains('requestIdleCallback') -and $pageSource.Contains('function ensureCatalogRendered'))) { throw "Catalog should incrementally render year sections after the initial viewport." }
if ($css.Contains('min-height: 38px') -or $css.Contains('min-height: 36px') -or $css.Contains('min-height: 34px') -or $css.Contains('width: 34px') -or $css.Contains('height: 34px')) { throw "Primary interactive controls should meet 44px touch target sizing." }
if (-not $pageSource.Contains('fetch("series_library_data.json"')) { throw "Public page should load static catalog JSON." }
if (-not $pageSource.Contains('fetch("series_library_details.json"')) { throw "Series detail modal should lazy-load detail JSON." }
if ($html.Contains('id="updateButton"')) { throw "Public page should not expose update controls." }
if ($pageSource.Contains('/api/update') -or $pageSource.Contains('EventSource')) { throw "Public page should not reference update APIs." }
if (-not ($vercelConfig.Contains('"source": "/"') -and $vercelConfig.Contains('"destination": "/series_library.html"'))) { throw "Missing Vercel root rewrite." }
if (-not $html.Contains('id="yearNav"')) { throw "Missing year navigation." }
if (-not $html.Contains('id="yearSelect"')) { throw "Missing year select." }
if (-not $html.Contains('id="categoryFilter"')) { throw "Missing category filter." }
if (-not ($html.Contains('id="filterPanel"') -and $css.Contains('.filter-summary') -and $pageSource.Contains('mobileFilterQuery'))) { throw "Mobile filters should collapse behind a responsive filter panel." }
if (-not $html.Contains('id="trendFilter"')) { throw "Missing trend filter." }
if (-not ($html.Contains('class="trend-choice"') -and $html.Contains('value="up"') -and $html.Contains('value="down"') -and $html.Contains('value="disaster"'))) { throw "Missing trend filter choices." }
if (-not $pageSource.Contains('"decade-group"')) { throw "Missing decade group renderer." }
if (-not $pageSource.Contains('class="poster"')) { throw "Missing poster markup." }
if (-not $html.Contains('id="search"')) { throw "Missing search input." }
if (-not $html.Contains('placeholder="Search titles..."')) { throw "Search input should be title-focused." }
if ($pageSource.Contains('class="synopsis"')) { throw "Cards should not render synopsis markup." }
if ($pageSource.Contains('data-search="${escapeText([item.title, item.synopsis')) { throw "Card search should not include synopsis." }
if (-not $html.Contains('id="seriesDetailModal"')) { throw "Missing series detail modal." }
if (-not $pageSource.Contains('class="detail-layout"')) { throw "Detail modal should use the poster/info/synopsis/season layout." }
if (-not $pageSource.Contains('class="detail-info"')) { throw "Detail modal should render card-style series info." }
if (-not $pageSource.Contains('class="detail-synopsis"')) { throw "Detail modal should render synopsis." }
if ($pageSource.Contains('class="detail-tags"')) { throw "Detail modal should not render a duplicate genre/tag row." }
if ($pageSource.Contains('class="detail-fact"')) { throw "Detail modal should not restate card facts as separate metric boxes." }
if (-not ($pageSource.Contains('role="button"') -and $pageSource.Contains('data-id="${escapeText(item.id)}"'))) { throw "Series cards should be keyboard-openable detail triggers." }
if (-not $pageSource.Contains('event.key !== "Enter" && event.key !== " "')) { throw "Series cards should open with Space as well as Enter." }
if (-not ($pageSource.Contains('function trapModalFocus') -and $pageSource.Contains('focusableSelectors'))) { throw "Series detail modal should trap keyboard focus while open." }
if ($pageSource.Contains('class="series-detail-foot"')) { throw "Series detail modal should not have a footer action bar." }
if ($pageSource.Contains('id="seriesDetailDone"')) { throw "Series detail modal should only use the close button." }
if ($pageSource.Contains('<a class="imdb-link fact"')) { throw "Series detail modal should not duplicate the IMDb link." }
if (-not $pageSource.Contains('class="season-table"')) { throw "Series detail modal should render season details." }
if (-not $pageSource.Contains('<span>Year</span>')) { throw "Series detail modal should render season years." }
if (-not $pageSource.Contains('class="season-score"')) { throw "Rated seasons should render as score pills." }
if (-not $pageSource.Contains('Pending')) { throw "Season ratings should show a pending state when rating data is unavailable." }
if (-not $pageSource.Contains('class="trend-tag')) { throw "Series cards should render trend tags." }
if (-not $pageSource.Contains('Trend Up')) { throw "Series cards should support Trend Up tags." }
if (-not $pageSource.Contains('Trend Down')) { throw "Series cards should support Trend Down tags." }
if (-not $pageSource.Contains('Disaster')) { throw "Series cards should support Disaster tags." }
if (-not $pageSource.Contains('data-trend="${escapeText(trendKind(item) || "")}"')) { throw "Series cards should expose trend data for filtering." }
if (-not ($pageSource.Contains('function imdbTitleUrl') -and $pageSource.Contains('href="${escapeText(imdbTitleUrl(item))}"'))) { throw "Series cards should derive IMDb links from title ids." }
if (-not ($pageSource.Contains('data-score="${escapeText(Number(item.score).toFixed(1))}"') -and $pageSource.Contains('data-primary-categories='))) { throw "Series cards should expose precomputed filter data." }
if (-not ($pageSource.Contains('function scheduleApplyFilters') -and $pageSource.Contains('requestAnimationFrame'))) { throw "Text and range filter inputs should batch DOM filtering work." }
if (-not $pageSource.Contains('slope >= 0.3')) { throw "Trend Up should use the softened 0.3 threshold." }
if (-not $pageSource.Contains('slope <= -0.3')) { throw "Trend Down should use the softened -0.3 threshold." }
if (-not $pageSource.Contains('function finiteSeasonScore')) { throw "Trend calculations should guard against pending null season scores." }
if (-not $pageSource.Contains('function ratedSeasonPoints')) { throw "Trend calculations should operate on rated seasons only." }
if ($pageSource.Contains('y: Number(season.score)')) { throw "Trend fallback should not cast pending null season scores to zero." }
if (-not $pageSource.Contains('lastScore - firstScore <= -1.5')) { throw "Disaster should use the 1.5 point drop threshold." }
