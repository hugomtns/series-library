$ErrorActionPreference = "Stop"

$data = Get-Content -Path "imdb_sci_fi_catalog_data.json" -Raw | ConvertFrom-Json
$html = Get-Content -Path "series_library.html" -Raw
$sourceRows = @(Import-Csv -Path "imdb_scifi_fantasy_series_by_year_all_primary_origin.csv")

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
  SourceRows = $sourceRows.Count
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
} | Format-List

if ($data.total -ne $sourceRows.Count) { throw "Catalog total does not match source CSV rows." }
if ($series.Count -ne $sourceRows.Count) { throw "Series rows do not match source CSV rows." }
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
