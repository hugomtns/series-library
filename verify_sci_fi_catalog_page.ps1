$ErrorActionPreference = "Stop"

$html = Get-Content -Path "series_library.html" -Raw
$css = Get-Content -Path "series_library.css" -Raw
$clientModulePaths = @(
  "series_library.js",
  "series_library_data_client.js",
  "series_library_rendering.js"
)
$clientJs = ($clientModulePaths | Where-Object { Test-Path -Path $_ } | ForEach-Object { Get-Content -Path $_ -Raw }) -join "`n"
$pageSource = "$html`n$clientJs"
$packageJson = Get-Content -Path "package.json" -Raw
$catalogBuilder = Get-Content -Path "build_sci_fi_catalog_page.ps1" -Raw
$combinedSourceScript = Get-Content -Path "build_combined_genre_catalog_source.ps1" -Raw
$catalogExporter = Get-Content -Path "scripts/export_public_catalog.js" -Raw
$migrationScript = Get-Content -Path "scripts/migrate_to_sqlite.js" -Raw
$trendRulesScript = Get-Content -Path "scripts/trend_rules.js" -Raw
$seasonRefreshScript = Get-Content -Path "scripts/refresh_open_series_seasons.ps1" -Raw
$currentYearSourcesScript = Get-Content -Path "scripts/update_current_year_sources.ps1" -Raw
$updateScript = Get-Content -Path "scripts/update_library.js" -Raw
$serverScript = Get-Content -Path "series_library_server.js" -Raw
$deployCheckScript = if (Test-Path -Path "scripts/check_deploy_ready.js") { Get-Content -Path "scripts/check_deploy_ready.js" -Raw } else { "" }
$verifyScript = Get-Content -Path "verify_sci_fi_catalog_page.ps1" -Raw
$publicDataJson = Get-Content -Path "series_library_data.json" -Raw
$publicDetailsJson = if (Test-Path -Path "series_library_details.json") { Get-Content -Path "series_library_details.json" -Raw } else { "" }
$publicData = $publicDataJson | ConvertFrom-Json
$publicDetails = if ($publicDetailsJson) { $publicDetailsJson | ConvertFrom-Json } else { $null }
$vercelConfig = Get-Content -Path "vercel.json" -Raw
$publicSchemaDoc = if (Test-Path -Path "docs/public_data_schema.md") { Get-Content -Path "docs/public_data_schema.md" -Raw } else { "" }
$env:SERIES_LIBRARY_DB = Join-Path (Resolve-Path ".") "series_library.db"
$dataJson = & node "scripts/read_catalog_for_verify.js"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read catalog from SQLite."
}
$data = $dataJson | ConvertFrom-Json

function Get-DetailRows($detailsPayload) {
  if ($null -eq $detailsPayload -or $null -eq $detailsPayload.series) { return @() }
  if ($detailsPayload.series -is [array]) { return @($detailsPayload.series) }
  return @($detailsPayload.series.PSObject.Properties | ForEach-Object { $_.Value })
}

function Test-ContainsAll($text, [string[]]$patterns) {
  foreach ($pattern in $patterns) {
    if (-not $text.Contains($pattern)) { return $false }
  }
  return $true
}

function Assert-Condition($condition, $message) {
  if (-not $condition) { throw $message }
}

$series = @($data.series)
$publicSeries = @($publicData.series)
$publicDetailSeries = Get-DetailRows $publicDetails
$publicDetailKeys = if ($null -ne $publicDetails -and $null -ne $publicDetails.series -and -not ($publicDetails.series -is [array])) { @($publicDetails.series.PSObject.Properties.Name) } else { @() }
$publicIndexRowsWithDetails = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "synopsis" -or $_.PSObject.Properties.Name -contains "seasonDetails" })
$publicIndexRowsWithTrendPayload = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "seasonTrend" })
$publicIndexRowsWithImdbUrl = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "imdbUrl" })
$publicIndexRowsWithPosterDimensions = @($publicSeries | Where-Object { $_.PSObject.Properties.Name -contains "posterWidth" -or $_.PSObject.Properties.Name -contains "posterHeight" })
$publicIndexRowsWithUnusedMetadata = @($publicSeries | Where-Object {
  $_.PSObject.Properties.Name -contains "votes" -or
  $_.PSObject.Properties.Name -contains "rank" -or
  $_.PSObject.Properties.Name -contains "type" -or
  $_.PSObject.Properties.Name -contains "seasons" -or
  $_.PSObject.Properties.Name -contains "episodes" -or
  $_.PSObject.Properties.Name -contains "genres" -or
  $_.PSObject.Properties.Name -contains "countries" -or
  $_.PSObject.Properties.Name -contains "countryCodes"
})
$publicCatalogHasSource = $publicData.PSObject.Properties.Name -contains "source"
$publicDetailRowsWithDetails = @($publicDetailSeries | Where-Object { $_.PSObject.Properties.Name -contains "synopsis" -and $_.PSObject.Properties.Name -contains "seasonDetails" })
$publicDetailSeasonRowsWithVotes = @($publicDetailSeries | ForEach-Object { @($_.seasonDetails) } | Where-Object { $_.PSObject.Properties.Name -contains "votes" })
$publicDetailSeasonRowsWithLabels = @($publicDetailSeries | ForEach-Object { @($_.seasonDetails) } | Where-Object { $_.PSObject.Properties.Name -contains "label" })
$publicDetailRowsWithIds = @($publicDetailSeries | Where-Object { $_.PSObject.Properties.Name -contains "id" })
$publicPayloadHasNullFields = $publicDataJson.Contains(':null') -or $publicDetailsJson.Contains(':null')
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
$hasExternalClientScript = $html.Contains('<script type="module" src="series_library.js"></script>') -and $clientJs.Contains('async function loadCatalogData')
$hasCatalogBuilderHtmlOutput = $catalogBuilder.Contains('$OutHtml') -or $catalogBuilder.Contains('$SkipHtml') -or $catalogBuilder.Contains('$html = @''') -or $catalogBuilder.Contains('<style>')
$hasExtractedCss = $css.Contains('.card') -and $css.Contains('.series-detail-modal')
$hasOrganizedCssSections = Test-ContainsAll $css @('/* Foundation */', '/* App Layout */', '/* Filters */', '/* Year Navigation */', '/* Toolbar */', '/* Catalog */', '/* Detail Modal */', '/* State Utilities */', '/* Responsive */')
$hasSharedFocusTokens = Test-ContainsAll $css @('--focus-ring:', '--card-focus-ring:', 'outline: var(--focus-ring)', 'box-shadow: var(--card-focus-ring)')
$hasControlSystem = Test-ContainsAll $css @('--control-bg:', '--control-border:', '--control-hover:', '.category-trigger,', '.score-field input,', '.reset-filters,', '.year-picker select,', '.search {', '.select-shell::after', 'appearance: none')
$hasPolishedControlIndicators = (Test-ContainsAll $css @('--active-shift:', 'border-right: 2px solid var(--muted)', 'linear-gradient(var(--muted), var(--muted)) center / 10px 2px no-repeat', '@media (prefers-reduced-motion: reduce)')) -and $hasControlSystem
$hasYearSectionRenderContainment = Test-ContainsAll $css @('content-visibility: auto', 'contain-intrinsic-size')
$hasIncrementalCatalogRender = Test-ContainsAll $pageSource @('requestIdleCallback', 'function ensureCatalogRendered')
$hasTouchSizedControls = -not ($css.Contains('min-height: 38px') -or $css.Contains('min-height: 36px') -or $css.Contains('min-height: 34px') -or $css.Contains('width: 34px') -or $css.Contains('height: 34px'))
$usesKeyedSeriesDetails = Test-ContainsAll $pageSource @('details.series || {}', 'detailMap[item.id]')
$hasVercelRootRewrite = Test-ContainsAll $vercelConfig @('"source": "/"', '"destination": "/series_library.html"')
$hasMobileFilterPanel = (Test-ContainsAll $html @('id="filterPanel"', 'id="filterPanelState"')) -and $css.Contains('.filter-summary') -and (Test-ContainsAll $pageSource @('mobileFilterQuery', 'function syncFilterPanelState'))
$hasNonOverlappingFilterMenus = $css.Contains('.category-menu') -and $css.Contains('margin-top: 5px') -and -not $css.Contains('top: calc(100% + 5px)')
$hasFilterMenuEscape = Test-ContainsAll $pageSource @('function closeOpenFilterMenu', 'closeOpenFilterMenu(true)')
$hasFilterReset = (Test-ContainsAll $html @('id="filterStatus"', 'id="resetFilters"')) -and (Test-ContainsAll $pageSource @('function updateFilterStatus', 'resetFilters.addEventListener("click"'))
$hasLiveFilterResults = (Test-ContainsAll $html @('id="metaLine" aria-live="polite"', 'id="empty" role="status"'))
$hasPosterPriorityLoading = Test-ContainsAll $pageSource @('priorityPosterBudgetStart', 'priorityPosterCount', 'isPriority ? "eager" : "lazy"', 'isPriority ? "high" : "auto"', 'decoding="async"')
$hasPosterErrorFallback = Test-ContainsAll $pageSource @('function handlePosterImageError', 'addEventListener("error", handlePosterImageError, true)')
$hasActionSeasonRefresh = $packageJson.Contains('refresh:action-seasons') -and $seasonRefreshScript.Contains('REFRESH_CATEGORY')
$hasCachedSeasonRefreshDefault = Test-ContainsAll $updateScript @('refresh_open_series_seasons.ps1', '"-SkipExisting"')
$hasParallelSeasonRefresh = (Test-ContainsAll $seasonRefreshScript @('[int]$Concurrency', 'Start-Job')) -and $updateScript.Contains('"-Concurrency", "2"')
$hasActionSourceConfig = $combinedSourceScript.Contains('imdb_action_year_files_primary_origin') -and $currentYearSourcesScript.Contains('Genre = "Action"')
$hasTrendFilterChoices = (Test-ContainsAll $html @('class="trend-choice"', 'value="up"', 'value="down"', 'value="disaster"'))
$hasDeadSeriesDetailHead = $html.Contains('id="seriesDetailHead"') -or $clientJs.Contains('seriesDetailHead') -or $css.Contains('.series-detail-head')
$hasClickableCards = Test-ContainsAll $pageSource @('role="button"', 'data-id="${escapeText(item.id)}"')
$hasModalFocusTrap = Test-ContainsAll $pageSource @('function trapModalFocus', 'focusableSelectors')
$hasModalScrollLock = (Test-ContainsAll $pageSource @('function lockPageScroll', 'function unlockPageScroll', 'const modalScrollY = window.scrollY', 'window.scrollTo(0, modalScrollY)')) -and (Test-ContainsAll $css @('body.modal-open', 'overscroll-behavior: contain')) -and -not $pageSource.Contains('body.style.top') -and -not $pageSource.Contains('lastSeriesTrigger.focus')
$hasDerivedImdbUrl = Test-ContainsAll $pageSource @('function imdbTitleUrl', 'href="${escapeText(imdbTitleUrl(item))}"')
$hasFilterDataAttributes = Test-ContainsAll $pageSource @('data-score="${escapeText(Number(item.score).toFixed(1))}"', 'data-primary-categories=')
$hasBatchedFilterInputs = Test-ContainsAll $pageSource @('function scheduleApplyFilters', 'requestAnimationFrame')
$usesExportedTrendFields = Test-ContainsAll $pageSource @('return item.trendKind || null', 'Number(item.trendSlope)')
$usesSharedTrendRulesInExport = Test-ContainsAll $catalogExporter @('require("./trend_rules")', 'getTrendKind')
$usesSharedTrendRulesInMigration = Test-ContainsAll $migrationScript @('require("./trend_rules")', 'calculateSeasonRatingTrend')
$hasExporterTrendPoints = Test-ContainsAll $trendRulesScript @('function getTrendKind', 'seasonTrendPoints(seasonDetails)')
$hasSharedTrendThresholds = Test-ContainsAll $trendRulesScript @('minRatedSeasons: 3', 'minRatedScore: 0.1', 'disasterDrop: -1.5', 'trendUpSlope: 0.3', 'trendDownSlope: -0.3')
$hasPublicSchemaDoc = Test-ContainsAll $publicSchemaDoc @(
  'series_library_data.json',
  'series_library_details.json',
  'id',
  'title',
  'year',
  'score',
  'poster',
  'seasonLabel',
  'primaryOrigin',
  'categories',
  'trendSlope',
  'trendKind',
  'synopsis',
  'seasonDetails',
  'Null Handling',
  'scripts/trend_rules.js'
)
$hasStaticServerAllowlist = Test-ContainsAll $serverScript @('const publicFiles = new Set', 'resolvePublicFile', 'publicFiles.has', 'series_library_data_client.js', 'series_library_rendering.js')
$hasStaticServerHeadHandling = Test-ContainsAll $serverScript @('req.method === "HEAD"', '"content-length": content.length')
$hasStaticServerHostConfig = Test-ContainsAll $serverScript @('process.env.HOST || "127.0.0.1"', 'server.listen(port, host')
$hasDeployCheck = $packageJson.Contains('"deploy:check"') -and $packageJson.Contains('npm run deploy:check') -and (Test-ContainsAll $deployCheckScript @('requiredPublicFiles', 'requiredIgnoredPaths', 'vercel.json should rewrite /', 'Deploy readiness check passed.'))

[pscustomobject]@{
  Total = $data.total
  PublicDataTotal = $publicData.total
  PublicDetailsTotal = if ($null -ne $publicDetails) { $publicDetails.total } else { 0 }
  PublicIndexRowsWithDetails = $publicIndexRowsWithDetails.Count
  PublicIndexRowsWithTrendPayload = $publicIndexRowsWithTrendPayload.Count
  PublicIndexRowsWithImdbUrl = $publicIndexRowsWithImdbUrl.Count
  PublicIndexRowsWithPosterDimensions = $publicIndexRowsWithPosterDimensions.Count
  PublicIndexRowsWithUnusedMetadata = $publicIndexRowsWithUnusedMetadata.Count
  PublicCatalogHasSource = $publicCatalogHasSource
  PublicDetailRowsWithDetails = $publicDetailRowsWithDetails.Count
  PublicDetailKeys = $publicDetailKeys.Count
  PublicDetailRowsWithIds = $publicDetailRowsWithIds.Count
  PublicDetailSeasonRowsWithVotes = $publicDetailSeasonRowsWithVotes.Count
  PublicDetailSeasonRowsWithLabels = $publicDetailSeasonRowsWithLabels.Count
  PublicPayloadHasNullFields = $publicPayloadHasNullFields
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
  HasExternalClientScript = $hasExternalClientScript
  HasInlineModuleScript = $html.Contains('<script type="module">')
  HasDeadYearNavigationCode = $clientJs.Contains('for (const yearInfo of data.years)')
  HasInlineNodeVerificationReader = $verifyScript.Contains('node ' + '-e')
  HasInlineStyleBlock = $html.Contains('<style>')
  HasCatalogBuilderHtmlOutput = $hasCatalogBuilderHtmlOutput
  HasExtractedCss = $hasExtractedCss
  HasOrganizedCssSections = $hasOrganizedCssSections
  HasSharedFocusTokens = $hasSharedFocusTokens
  HasControlSystem = $hasControlSystem
  HasPolishedControlIndicators = $hasPolishedControlIndicators
  HasPublicSchemaDoc = $hasPublicSchemaDoc
  HasStaticServerAllowlist = $hasStaticServerAllowlist
  HasStaticServerHeadHandling = $hasStaticServerHeadHandling
  HasStaticServerHostConfig = $hasStaticServerHostConfig
  HasDeployCheck = $hasDeployCheck
  HasYearSectionRenderContainment = $hasYearSectionRenderContainment
  HasIncrementalCatalogRender = $hasIncrementalCatalogRender
  HasTouchSizedControls = $hasTouchSizedControls
  UsesStaticCatalogJson = $pageSource.Contains('fetch("series_library_data.json"')
  UsesLazySeriesDetailsJson = $pageSource.Contains('fetch("series_library_details.json"')
  UsesKeyedSeriesDetails = $usesKeyedSeriesDetails
  HasUpdateButton = $html.Contains('id="updateButton"')
  HasUpdateApiReference = $pageSource.Contains('/api/update') -or $pageSource.Contains('EventSource')
  HasVercelRootRewrite = $hasVercelRootRewrite
  HasYearSelect = $html.Contains('id="yearSelect"')
  HasCategoryFilter = $html.Contains('id="categoryFilter"')
  HasMobileFilterPanel = $hasMobileFilterPanel
  HasNonOverlappingFilterMenus = $hasNonOverlappingFilterMenus
  HasFilterMenuEscape = $hasFilterMenuEscape
  HasFilterReset = $hasFilterReset
  HasLiveFilterResults = $hasLiveFilterResults
  HasPosterPriorityLoading = $hasPosterPriorityLoading
  HasPosterErrorFallback = $hasPosterErrorFallback
  HasActionCategoryFilter = $html.Contains('class="category-choice" value="Action"')
  HasActionSeasonRefresh = $hasActionSeasonRefresh
  HasCachedSeasonRefreshDefault = $hasCachedSeasonRefreshDefault
  HasParallelSeasonRefresh = $hasParallelSeasonRefresh
  HasTrendFilter = $html.Contains('id="trendFilter"')
  HasActionSourceConfig = $hasActionSourceConfig
  HasTrendFilterChoices = $hasTrendFilterChoices
  HasDecadeGroups = $pageSource.Contains('"decade-group"')
  HasPosterMarkup = $pageSource.Contains('class="poster"')
  HasSearch = $html.Contains('id="search"')
  HasTitleSearchPlaceholder = $html.Contains('placeholder="Search titles..."')
  HasSynopsisMarkup = $pageSource.Contains('class="synopsis"')
  CardSearchIncludesSynopsis = $pageSource.Contains('data-search="${escapeText([item.title, item.synopsis')
  HasSeriesDetailModal = $html.Contains('id="seriesDetailModal"')
  HasDeadSeriesDetailHead = $hasDeadSeriesDetailHead
  HasSeriesDetailSynopsis = $pageSource.Contains('class="detail-synopsis"')
  HasClickableCards = $hasClickableCards
  HasCardSpaceActivation = $pageSource.Contains('event.key !== "Enter" && event.key !== " "')
  HasModalFocusTrap = $hasModalFocusTrap
  HasModalScrollLock = $hasModalScrollLock
  HasSeriesDetailFooter = $pageSource.Contains('class="series-detail-foot"')
  HasSeriesDetailDone = $pageSource.Contains('id="seriesDetailDone"')
  HasSeriesDetailImdbLink = $pageSource.Contains('<a class="imdb-link fact"')
  HasSeriesDetailLayout = $pageSource.Contains('class="detail-layout"')
  HasSeriesDetailInfo = $pageSource.Contains('class="detail-info"')
  HasDetailDuplicateTags = $pageSource.Contains('class="detail-tags"')
  HasSeasonDetailTable = $pageSource.Contains('class="season-table"')
  HasDeadUpdateLogClass = $pageSource.Contains('update-log-') -or $css.Contains('update-log-')
  HasSeasonPendingState = $pageSource.Contains('Pending')
  HasTrendTag = $pageSource.Contains('class="trend-tag')
  HasTrendUp = $pageSource.Contains('Trend Up')
  HasTrendDown = $pageSource.Contains('Trend Down')
  HasDisaster = $pageSource.Contains('Disaster')
  HasCardTrendDataset = $pageSource.Contains('data-trend="${escapeText(trendKind(item) || "")}"')
  HasDerivedImdbUrl = $hasDerivedImdbUrl
  HasFilterDataAttributes = $hasFilterDataAttributes
  HasBatchedFilterInputs = $hasBatchedFilterInputs
  UsesExportedTrendFields = $usesExportedTrendFields
  UsesSharedTrendRulesInExport = $usesSharedTrendRulesInExport
  UsesSharedTrendRulesInMigration = $usesSharedTrendRulesInMigration
  HasSoftTrendUpThreshold = $trendRulesScript.Contains('slope >= TREND_RULES.trendUpSlope')
  HasSoftTrendDownThreshold = $trendRulesScript.Contains('slope <= TREND_RULES.trendDownSlope')
  HasFiniteSeasonScoreGuard = $trendRulesScript.Contains('function finiteSeasonScore')
  HasExporterTrendPoints = $hasExporterTrendPoints
  HasUnsafeSeasonScoreNumberCast = $pageSource.Contains('y: Number(season.score)')
  HasDisasterThreshold = $trendRulesScript.Contains('lastScore - firstScore <= TREND_RULES.disasterDrop')
  HasDeadRankStyle = $css.Contains('.rank')
} | Format-List

if ($data.total -ne $series.Count) { throw "Catalog total does not match SQLite series rows." }
if ($publicData.total -ne $data.total) { throw "Public JSON total does not match SQLite catalog total." }
if ($null -eq $publicDetails -or $publicDetails.total -ne $data.total) { throw "Public detail JSON total does not match SQLite catalog total." }
if ($publicIndexRowsWithDetails.Count -gt 0) { throw "Public index JSON should not include modal-only synopsis or season detail payloads." }
if ($publicIndexRowsWithTrendPayload.Count -gt 0) { throw "Public index JSON should expose compact trend fields instead of the full seasonTrend payload." }
if ($publicIndexRowsWithImdbUrl.Count -gt 0) { throw "Public index JSON should derive IMDb links from title ids instead of storing imdbUrl per row." }
if ($publicIndexRowsWithPosterDimensions.Count -gt 0) { throw "Public index JSON should not include unused poster dimension fields." }
if ($publicIndexRowsWithUnusedMetadata.Count -gt 0) { throw "Public index JSON should not include metadata fields unused by the UI." }
if ($publicCatalogHasSource) { throw "Public index JSON should not include unused source metadata." }
if ($publicDetailRowsWithDetails.Count -ne $data.total) { throw "Public detail JSON should include one detail payload per series." }
if ($publicDetailKeys.Count -ne $data.total) { throw "Public detail JSON should be keyed by series id." }
if ($publicDetailRowsWithIds.Count -gt 0) { throw "Public detail JSON should not repeat id fields inside detail rows." }
if ($publicDetailSeasonRowsWithVotes.Count -gt 0) { throw "Public detail JSON should not include unused season vote counts." }
if ($publicDetailSeasonRowsWithLabels.Count -gt 0) { throw "Public detail JSON should not include unused season label fields." }
if ($publicPayloadHasNullFields) { throw "Public JSON should omit null-valued fields." }
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
Assert-Condition $hasActionSeasonRefresh "Missing Action season refresh command."
Assert-Condition $hasCachedSeasonRefreshDefault "Full update should skip complete season caches by default."
Assert-Condition $hasParallelSeasonRefresh "Season refresh should support bounded parallelism for full updates."
Assert-Condition $hasActionSourceConfig "Missing Action source configuration."
if (-not $html.Contains('href="series_library.css"')) { throw "Missing extracted stylesheet link." }
Assert-Condition $hasExternalClientScript "Public page should load extracted client JavaScript."
if ($html.Contains('<script type="module">')) { throw "HTML should not contain the inline app module." }
if ($clientJs.Contains('for (const yearInfo of data.years)')) { throw "Client script should not keep dead year navigation code." }
if ($verifyScript.Contains('node ' + '-e')) { throw "Verification should use a checked-in Node helper instead of inline JavaScript." }
if ($html.Contains('<style>')) { throw "HTML should not contain an inline style block." }
Assert-Condition (-not $hasCatalogBuilderHtmlOutput) "Catalog builder should not contain dead HTML generation code."
Assert-Condition $hasExtractedCss "Extracted stylesheet is missing expected UI styles."
Assert-Condition $hasOrganizedCssSections "Stylesheet should keep major UI regions organized into labeled sections."
Assert-Condition $hasSharedFocusTokens "Stylesheet should use shared focus ring tokens instead of repeated literal rings."
Assert-Condition $hasControlSystem "Controls should share a standardized visual system."
Assert-Condition $hasPolishedControlIndicators "Control indicators and motion preferences should be polished."
Assert-Condition $hasPublicSchemaDoc "Public JSON schema should be documented."
Assert-Condition $hasStaticServerAllowlist "Local static server should only expose public app files."
Assert-Condition $hasStaticServerHeadHandling "Local static server should handle HEAD without sending a response body."
Assert-Condition $hasStaticServerHostConfig "Local static server should allow HOST override while defaulting to loopback."
Assert-Condition $hasDeployCheck "Deployment readiness should be covered by npm test."
Assert-Condition $hasYearSectionRenderContainment "Year sections should use render containment for offscreen catalog performance."
Assert-Condition $hasIncrementalCatalogRender "Catalog should incrementally render year sections after the initial viewport."
Assert-Condition $hasTouchSizedControls "Primary interactive controls should meet 44px touch target sizing."
if (-not $pageSource.Contains('fetch("series_library_data.json"')) { throw "Public page should load static catalog JSON." }
if (-not $pageSource.Contains('fetch("series_library_details.json"')) { throw "Series detail modal should lazy-load detail JSON." }
Assert-Condition $usesKeyedSeriesDetails "Series detail modal should read id-keyed detail JSON."
if ($html.Contains('id="updateButton"')) { throw "Public page should not expose update controls." }
if ($pageSource.Contains('/api/update') -or $pageSource.Contains('EventSource')) { throw "Public page should not reference update APIs." }
Assert-Condition $hasVercelRootRewrite "Missing Vercel root rewrite."
if (-not $html.Contains('id="yearNav"')) { throw "Missing year navigation." }
if (-not $html.Contains('id="yearSelect"')) { throw "Missing year select." }
if (-not $html.Contains('id="categoryFilter"')) { throw "Missing category filter." }
Assert-Condition $hasMobileFilterPanel "Mobile filters should collapse behind a responsive filter panel."
Assert-Condition $hasNonOverlappingFilterMenus "Filter menus should not overlap adjacent filter controls."
Assert-Condition $hasFilterMenuEscape "Filter menus should close with Escape and restore trigger focus."
Assert-Condition $hasFilterReset "Filters should expose a reset control and active-filter status."
Assert-Condition $hasLiveFilterResults "Filter result counts should be announced to assistive technology."
if (-not $html.Contains('id="trendFilter"')) { throw "Missing trend filter." }
Assert-Condition $hasTrendFilterChoices "Missing trend filter choices."
if (-not $pageSource.Contains('"decade-group"')) { throw "Missing decade group renderer." }
if (-not $pageSource.Contains('class="poster"')) { throw "Missing poster markup." }
Assert-Condition $hasPosterPriorityLoading "Poster images should prioritize the initial viewport and lazy-load the rest."
Assert-Condition $hasPosterErrorFallback "Poster images should fall back cleanly when a poster URL fails."
if (-not $html.Contains('id="search"')) { throw "Missing search input." }
if (-not $html.Contains('placeholder="Search titles..."')) { throw "Search input should be title-focused." }
if ($pageSource.Contains('class="synopsis"')) { throw "Cards should not render synopsis markup." }
if ($pageSource.Contains('data-search="${escapeText([item.title, item.synopsis')) { throw "Card search should not include synopsis." }
if (-not $html.Contains('id="seriesDetailModal"')) { throw "Missing series detail modal." }
Assert-Condition (-not $hasDeadSeriesDetailHead) "Series detail modal should not keep the unused header shell."
if (-not $pageSource.Contains('class="detail-layout"')) { throw "Detail modal should use the poster/info/synopsis/season layout." }
if (-not $pageSource.Contains('class="detail-info"')) { throw "Detail modal should render card-style series info." }
if (-not $pageSource.Contains('class="detail-synopsis"')) { throw "Detail modal should render synopsis." }
if ($pageSource.Contains('class="detail-tags"')) { throw "Detail modal should not render a duplicate genre/tag row." }
if ($pageSource.Contains('class="detail-fact"')) { throw "Detail modal should not restate card facts as separate metric boxes." }
Assert-Condition $hasClickableCards "Series cards should be keyboard-openable detail triggers."
if (-not $pageSource.Contains('event.key !== "Enter" && event.key !== " "')) { throw "Series cards should open with Space as well as Enter." }
Assert-Condition $hasModalFocusTrap "Series detail modal should trap keyboard focus while open."
Assert-Condition $hasModalScrollLock "Series detail modal should lock background scrolling while open without forcing focus-driven scroll restoration."
if ($pageSource.Contains('class="series-detail-foot"')) { throw "Series detail modal should not have a footer action bar." }
if ($pageSource.Contains('id="seriesDetailDone"')) { throw "Series detail modal should only use the close button." }
if ($pageSource.Contains('<a class="imdb-link fact"')) { throw "Series detail modal should not duplicate the IMDb link." }
if (-not $pageSource.Contains('class="season-table"')) { throw "Series detail modal should render season details." }
if ($pageSource.Contains('update-log-') -or $css.Contains('update-log-')) { throw "Public page should not keep update-log UI class names." }
if (-not $pageSource.Contains('<span>Year</span>')) { throw "Series detail modal should render season years." }
if (-not $pageSource.Contains('class="season-score"')) { throw "Rated seasons should render as score pills." }
if (-not $pageSource.Contains('Pending')) { throw "Season ratings should show a pending state when rating data is unavailable." }
if (-not $pageSource.Contains('class="trend-tag')) { throw "Series cards should render trend tags." }
if (-not $pageSource.Contains('Trend Up')) { throw "Series cards should support Trend Up tags." }
if (-not $pageSource.Contains('Trend Down')) { throw "Series cards should support Trend Down tags." }
if (-not $pageSource.Contains('Disaster')) { throw "Series cards should support Disaster tags." }
if (-not $pageSource.Contains('data-trend="${escapeText(trendKind(item) || "")}"')) { throw "Series cards should expose trend data for filtering." }
Assert-Condition $hasDerivedImdbUrl "Series cards should derive IMDb links from title ids."
Assert-Condition $hasFilterDataAttributes "Series cards should expose precomputed filter data."
Assert-Condition $hasBatchedFilterInputs "Text and range filter inputs should batch DOM filtering work."
Assert-Condition $usesExportedTrendFields "Series cards should use exported trend fields."
Assert-Condition $usesSharedTrendRulesInExport "Public export should use shared trend rules."
Assert-Condition $usesSharedTrendRulesInMigration "SQLite migration should use shared trend rules."
Assert-Condition $hasSharedTrendThresholds "Shared trend rules should define the expected thresholds."
if (-not $trendRulesScript.Contains('slope >= TREND_RULES.trendUpSlope')) { throw "Trend Up should use the softened 0.3 threshold." }
if (-not $trendRulesScript.Contains('slope <= TREND_RULES.trendDownSlope')) { throw "Trend Down should use the softened -0.3 threshold." }
if (-not $trendRulesScript.Contains('function finiteSeasonScore')) { throw "Trend calculations should guard against pending null season scores." }
Assert-Condition $hasExporterTrendPoints "Trend calculations should operate on rated seasons only."
if ($pageSource.Contains('y: Number(season.score)')) { throw "Trend fallback should not cast pending null season scores to zero." }
if (-not $trendRulesScript.Contains('lastScore - firstScore <= TREND_RULES.disasterDrop')) { throw "Disaster should use the 1.5 point drop threshold." }
if ($css.Contains('.rank')) { throw "Stylesheet should not keep unused rank styles." }
