param(
  [string]$SourceCsv = "scripts/.generated/catalog_source.csv",
  [string]$CacheDir = "imdb_sci_fi_catalog_cache",
  [string]$OutData = "scripts/.generated/catalog_data.json",
  [string]$OutHtml = "series_library.html",
  [int]$ThrottleMilliseconds = 700,
  [switch]$SkipFetch,
  [switch]$SkipHtml
)

$ErrorActionPreference = "Stop"

function Invoke-ImdbApi {
  param([string]$Uri)

  for ($attempt = 1; $attempt -le 8; $attempt++) {
    try {
      $result = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 45
      Start-Sleep -Milliseconds $ThrottleMilliseconds
      return $result
    } catch {
      $message = $_.Exception.Message
      if ($attempt -eq 8) {
        throw "IMDb API request failed after $attempt attempts. Last error: $message"
      }

      $delaySeconds = [math]::Min(180, 20 * $attempt)
      Write-Host "API request failed ($message). Waiting $delaySeconds seconds before retry $($attempt + 1)..."
      Start-Sleep -Seconds $delaySeconds
    }
  }
}

function Get-TitleDetailsBatch {
  param([string[]]$TitleIds)

  $query = ($TitleIds | ForEach-Object { "titleIds=$([uri]::EscapeDataString($_))" }) -join "&"
  $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles:batchGet?$query"
  return @($response.titles)
}

function Get-Seasons {
  param([string]$TitleId)

  $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles/$TitleId/seasons"
  return @($response.seasons)
}

function Set-RefreshValue {
  param([object]$Cached, [string]$Name, [string]$Value)

  if ($null -eq $Cached.refresh) {
    $Cached | Add-Member -NotePropertyName refresh -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $Cached.refresh | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-NumericSeasonCount {
  param([object[]]$Seasons)

  $numeric = @($Seasons | Where-Object { "$($_.season)" -match "^\d+$" })
  return $numeric.Count
}

function Get-YearText {
  param([object]$Row)

  if ($Row.EndYear) {
    return "$($Row.StartYear)-$($Row.EndYear)"
  }

  return "$($Row.StartYear)-"
}

function Repair-Text {
  param([string]$Text)

  if ([string]::IsNullOrEmpty($Text)) {
    return $Text
  }

  $hasMojibakeMarker = $false
  foreach ($char in $Text.ToCharArray()) {
    $code = [int][char]$char
    if ($code -eq 0x00C2 -or $code -eq 0x00C3 -or $code -eq 0x00E2) {
      $hasMojibakeMarker = $true
      break
    }
  }

  if ($hasMojibakeMarker) {
    try {
      $latin1Candidate = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(28591).GetBytes($Text))
      $stillHasMarker = $false
      foreach ($char in $latin1Candidate.ToCharArray()) {
        $code = [int][char]$char
        if ($code -eq 0x00C2 -or $code -eq 0x00C3 -or $code -eq 0x00E2) {
          $stillHasMarker = $true
          break
        }
      }

      if (-not $stillHasMarker) {
        return $latin1Candidate
      }

      return [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(1252).GetBytes($Text))
    } catch {
      return $Text
    }
  }

  return $Text
}

function Convert-ToCatalogItem {
  param(
    [object]$Row,
    [object]$Cached
  )

  $detail = $Cached.detail
  $seasons = if ($null -eq $Cached.seasons) { @() } else { @($Cached.seasons) }
  $seasonCount = Get-NumericSeasonCount -Seasons $seasons
  $genres = @($detail.genres | ForEach-Object { Repair-Text -Text $_ })

  $categories = @("$($Row.Categories)".Split(";", [System.StringSplitOptions]::RemoveEmptyEntries))
  if ($genres -contains "Animation" -and $categories -notcontains "Animation") {
    $categories += "Animation"
  }

  [pscustomobject]@{
    year = [int]$Row.Year
    rank = [int]$Row.Rank
    id = $Row.IMDbId
    title = Repair-Text -Text $(if ($detail.primaryTitle) { $detail.primaryTitle } else { $Row.Title })
    score = [double]$Row.IMDbScore
    votes = [int]$Row.Votes
    years = Get-YearText -Row $Row
    type = $Row.Type
    imdbUrl = $Row.IMDbUrl
    poster = if ($detail.primaryImage.url) { $detail.primaryImage.url } else { "" }
    posterWidth = if ($detail.primaryImage.width) { [int]$detail.primaryImage.width } else { $null }
    posterHeight = if ($detail.primaryImage.height) { [int]$detail.primaryImage.height } else { $null }
    synopsis = Repair-Text -Text $(if ($detail.plot) { $detail.plot } else { "No synopsis available." })
    seasons = $seasonCount
    seasonLabel = if ($seasonCount -eq 1) { "1 season" } elseif ($seasonCount -gt 1) { "$seasonCount seasons" } else { "Seasons unavailable" }
    episodes = [int](@($seasons | Measure-Object -Property episodeCount -Sum).Sum)
    genres = $genres
    countries = Repair-Text -Text $Row.OriginCountries
    countryCodes = $Row.OriginCountryCodes
    primaryOrigin = $Row.PrimaryOriginCountryCode
    categories = $categories
  }
}

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

$sourceRows = @(Import-Csv -Path $SourceCsv)
$ids = @($sourceRows | ForEach-Object { $_.IMDbId } | Sort-Object -Unique)

if (-not $SkipFetch) {
  Write-Host "Caching details and seasons for $($ids.Count) titles..."

  for ($i = 0; $i -lt $ids.Count; $i += 5) {
    $chunkSize = [math]::Min(5, $ids.Count - $i)
    $chunk = $ids[$i..($i + $chunkSize - 1)]
    $missingDetails = @($chunk | Where-Object {
      $cachePath = Join-Path $CacheDir "$_.json"
      -not (Test-Path -Path $cachePath)
    })

    if ($missingDetails.Count -gt 0) {
      foreach ($detail in (Get-TitleDetailsBatch -TitleIds $missingDetails)) {
        $cachePath = Join-Path $CacheDir "$($detail.id).json"
        $checkedAt = (Get-Date).ToUniversalTime().ToString("o")
        [pscustomobject]@{
          id = $detail.id
          detail = $detail
          seasons = $null
          refresh = [pscustomobject]@{
            lastRatingCheckAt = $checkedAt
            lastDetailCheckAt = $checkedAt
          }
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $cachePath -Encoding UTF8
      }
    }
  }

  $index = 0
  foreach ($id in $ids) {
    $index++
    $cachePath = Join-Path $CacheDir "$id.json"
    if (-not (Test-Path -Path $cachePath)) {
      Write-Host "Skipping $id because detail cache is missing."
      continue
    }

    $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
    if ($null -ne $cached.seasons) {
      continue
    }

    Write-Host "Fetching seasons $index/$($ids.Count): $id"
    $cached.seasons = @(Get-Seasons -TitleId $id)
    Set-RefreshValue -Cached $cached -Name "lastSeasonCheckAt" -Value (Get-Date).ToUniversalTime().ToString("o")
    $cached | ConvertTo-Json -Depth 20 | Set-Content -Path $cachePath -Encoding UTF8
  }
}

$items = New-Object System.Collections.Generic.List[object]
foreach ($row in $sourceRows) {
  $cachePath = Join-Path $CacheDir "$($row.IMDbId).json"
  if (-not (Test-Path -Path $cachePath)) {
    throw "Missing cache for $($row.IMDbId). Run without -SkipFetch first."
  }

  $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
  $items.Add((Convert-ToCatalogItem -Row $row -Cached $cached))
}

$years = @($items | Group-Object year | Sort-Object { [int]$_.Name } | ForEach-Object {
  [pscustomobject]@{
    year = [int]$_.Name
    count = $_.Count
  }
})

$data = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  source = "IMDbAPI via imdbapi.dev, filtered to primary-origin US/UK/Canada/Europe/Australia/New Zealand, Sci-Fi/Fantasy/Adventure, min 5000 votes"
  total = $items.Count
  years = $years
  series = @($items | Sort-Object year, rank)
}

$json = $data | ConvertTo-Json -Depth 20
$outDataDir = [io.path]::GetDirectoryName($OutData)
if (-not [string]::IsNullOrWhiteSpace($outDataDir)) {
  New-Item -ItemType Directory -Path $outDataDir -Force | Out-Null
}
$json | Set-Content -Path $OutData -Encoding UTF8

if ($SkipHtml) {
  Write-Host "Wrote $($items.Count) catalog items to $OutData"
  Write-Host "Skipped HTML page rebuild"
  return
}

$html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" href="data:,">
  <title>Series Library</title>
  <style>
    :root {
      color-scheme: light;
      --bg: oklch(96.8% 0.008 250);
      --panel: oklch(99.2% 0.006 250);
      --panel-2: oklch(93.5% 0.012 250);
      --ink: oklch(19% 0.018 250);
      --muted: oklch(47% 0.018 250);
      --line: oklch(86% 0.014 250);
      --accent: oklch(54% 0.17 35);
      --accent-soft: oklch(91% 0.052 35);
      --focus: oklch(58% 0.18 250);
      --shadow: 0 18px 55px oklch(22% 0.018 250 / 0.13);
    }

    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
      background: var(--bg);
      color: var(--ink);
      letter-spacing: 0;
    }

    a { color: inherit; }

    .shell {
      min-height: 100vh;
      display: grid;
      grid-template-columns: 280px minmax(0, 1fr);
    }

    .sidebar {
      position: sticky;
      top: 0;
      height: 100vh;
      padding: 24px 18px;
      background: oklch(98.2% 0.01 250);
      border-right: 1px solid var(--line);
      overflow: auto;
    }

    .brand {
      display: grid;
      gap: 8px;
      margin-bottom: 20px;
    }

    h1 {
      margin: 0;
      font-size: 1.35rem;
      line-height: 1.15;
      letter-spacing: 0;
    }

    .subhead {
      margin: 0;
      color: var(--muted);
      font-size: 0.88rem;
      line-height: 1.45;
    }

    .stats {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
      margin: 18px 0;
    }

    .category-filter {
      position: relative;
      margin: 0 0 14px;
    }

    .category-trigger {
      width: 100%;
      min-height: 38px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      color: var(--ink);
      padding: 0 10px;
      font: inherit;
      font-size: 0.82rem;
      font-weight: 700;
      cursor: pointer;
      transition: border-color 160ms ease, background-color 160ms ease;
    }

    .category-trigger:hover,
    .category-trigger:focus-visible {
      outline: none;
      border-color: var(--focus);
    }

    .category-trigger::after {
      content: "v";
      color: var(--muted);
      font-size: 0.78rem;
    }

    .category-filter.open .category-trigger::after {
      content: "^";
    }

    .category-menu {
      display: none;
      position: absolute;
      z-index: 20;
      top: calc(100% + 5px);
      left: 0;
      right: 0;
      padding: 7px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: var(--shadow);
    }

    .category-filter.open .category-menu {
      display: grid;
      gap: 4px;
    }

    .category-option {
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 32px;
      padding: 5px 7px;
      border-radius: 6px;
      font-size: 0.82rem;
      cursor: pointer;
    }

    .score-filter {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
      margin: 0 0 14px;
    }

    .score-field {
      display: grid;
      gap: 5px;
    }

    .score-field label {
      color: var(--muted);
      font-size: 0.72rem;
      font-weight: 650;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .score-field input {
      width: 100%;
      min-height: 36px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      color: var(--ink);
      padding: 0 9px;
      font: inherit;
    }

    .score-field input:focus {
      outline: 2px solid oklch(70% 0.12 250 / 0.38);
      border-color: var(--focus);
    }

    .category-option:hover {
      background: var(--panel-2);
    }

    .category-option input {
      margin: 0;
      accent-color: oklch(54% 0.17 35);
    }

    .category-option.all {
      font-weight: 750;
      border-bottom: 1px solid var(--line);
      border-radius: 6px 6px 0 0;
      margin-bottom: 2px;
      padding-bottom: 8px;
    }

    .stat {
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
    }

    .stat strong {
      display: block;
      font-size: 1.1rem;
      line-height: 1.2;
    }

    .stat span {
      display: block;
      color: var(--muted);
      font-size: 0.74rem;
      margin-top: 2px;
    }

    .year-picker {
      display: grid;
      gap: 6px;
      margin: 18px 0 12px;
    }

    .year-picker span,
    .nav-label {
      color: var(--muted);
      font-size: 0.74rem;
      font-weight: 650;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .year-picker select {
      min-height: 38px;
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      color: var(--ink);
      padding: 0 10px;
      font: inherit;
    }

    .year-picker select:focus {
      outline: 2px solid oklch(70% 0.12 250 / 0.38);
      border-color: var(--focus);
    }

    .year-nav {
      display: grid;
      gap: 8px;
    }

    .decade-group {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      overflow: hidden;
    }

    .decade-group summary {
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 9px 10px;
      font-size: 0.84rem;
      font-weight: 700;
      list-style: none;
    }

    .decade-group summary::-webkit-details-marker { display: none; }

    .decade-group summary::after {
      content: "+";
      color: var(--muted);
      font-weight: 700;
    }

    .decade-group[open] summary::after { content: "-"; }

    .decade-count {
      color: var(--muted);
      font-size: 0.72rem;
      font-weight: 500;
      margin-left: auto;
    }

    .decade-years {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 6px;
      padding: 0 8px 8px;
    }

    .year-nav a {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 34px;
      padding: 7px 8px;
      border: 1px solid var(--line);
      border-radius: 7px;
      background: var(--panel);
      text-decoration: none;
      font-size: 0.82rem;
      transition: border-color 160ms ease, background-color 160ms ease, color 160ms ease;
    }

    .year-nav a:hover,
    .year-nav a:focus-visible {
      border-color: var(--focus);
      outline: none;
    }

    .year-nav a.active {
      background: var(--accent-soft);
      border-color: oklch(78% 0.075 35);
      color: oklch(32% 0.07 35);
    }

    .year-nav small {
      color: var(--muted);
      font-size: 0.68rem;
    }

    .content {
      padding: 28px 34px 60px;
      min-width: 0;
    }

    .toolbar {
      position: sticky;
      top: 0;
      z-index: 5;
      display: grid;
      grid-template-columns: minmax(220px, 420px) auto;
      gap: 14px;
      align-items: center;
      padding: 0 0 18px;
      background: linear-gradient(var(--bg) 72%, oklch(96.8% 0.008 250 / 0));
    }

    .search {
      width: 100%;
      min-height: 42px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      color: var(--ink);
      padding: 0 12px;
      font: inherit;
    }

    .search:focus {
      outline: 2px solid oklch(70% 0.12 250 / 0.38);
      border-color: var(--focus);
    }

    .meta-line {
      justify-self: end;
      color: var(--muted);
      font-size: 0.86rem;
    }

    .year-section {
      scroll-margin-top: 82px;
      margin-bottom: 44px;
    }

    .year-heading {
      display: flex;
      align-items: baseline;
      gap: 12px;
      margin: 0 0 15px;
      padding-bottom: 10px;
      border-bottom: 1px solid var(--line);
    }

    .year-heading h2 {
      margin: 0;
      font-size: 1.7rem;
      line-height: 1.15;
      letter-spacing: 0;
    }

    .year-heading span {
      color: var(--muted);
      font-size: 0.9rem;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(330px, 1fr));
      gap: 14px;
    }

    .card {
      display: grid;
      grid-template-columns: 92px minmax(0, 1fr);
      gap: 13px;
      min-height: 150px;
      padding: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      box-shadow: 0 1px 0 oklch(100% 0 0 / 0.65) inset;
      cursor: pointer;
      transition: border-color 160ms ease, box-shadow 160ms ease, background-color 160ms ease;
    }

    .card:hover,
    .card:focus-visible {
      border-color: var(--focus);
      box-shadow: 0 0 0 2px oklch(70% 0.12 250 / 0.18);
      outline: none;
    }

    .poster {
      width: 92px;
      aspect-ratio: 2 / 3;
      border-radius: 6px;
      background: var(--panel-2);
      border: 1px solid var(--line);
      overflow: hidden;
      align-self: start;
    }

    .poster img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .poster-fallback {
      height: 100%;
      display: grid;
      place-items: center;
      padding: 8px;
      color: var(--muted);
      font-size: 0.76rem;
      text-align: center;
    }

    .card-main {
      min-width: 0;
      display: grid;
      gap: 8px;
    }

    .card-top {
      display: grid;
      gap: 5px;
    }

    .title-row {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 10px;
      align-items: start;
    }

    .title {
      margin: 0;
      font-size: 1rem;
      line-height: 1.22;
      letter-spacing: 0;
      overflow-wrap: anywhere;
    }

    .rating {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 3px 7px;
      border-radius: 999px;
      background: var(--rating-bg, oklch(94% 0.05 92));
      color: var(--rating-fg, oklch(22% 0.018 250));
      border: 1px solid var(--rating-border, oklch(80% 0.04 92));
      font-weight: 700;
      font-size: 0.82rem;
      white-space: nowrap;
    }

    .facts {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;
      color: var(--muted);
      font-size: 0.78rem;
    }

    .fact {
      display: inline-flex;
      align-items: center;
      min-height: 22px;
      padding: 2px 7px;
      border-radius: 999px;
      background: var(--panel-2);
    }

    .category-chip {
      background: oklch(92% 0.03 250);
      color: oklch(34% 0.055 250);
    }

    .card-actions {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 10px;
      margin-top: 2px;
    }

    .rank {
      color: var(--muted);
      font-size: 0.78rem;
    }

    .imdb-link {
      color: oklch(38% 0.105 35);
      font-weight: 650;
      text-decoration: none;
      font-size: 0.82rem;
    }

    .imdb-link:hover,
    .imdb-link:focus-visible {
      text-decoration: underline;
      outline: none;
    }

    .empty {
      display: none;
      padding: 28px;
      border: 1px dashed var(--line);
      border-radius: 8px;
      color: var(--muted);
      background: var(--panel);
    }

    .series-detail-backdrop {
      position: fixed;
      inset: 0;
      z-index: 25;
      display: grid;
      place-items: center;
      padding: 24px;
      background: oklch(18% 0.018 250 / 0.45);
    }

    .series-detail-backdrop[hidden] { display: none; }

    .series-detail-modal {
      width: min(820px, calc(100vw - 32px));
      max-height: min(82vh, 820px);
      display: grid;
      grid-template-rows: auto minmax(0, 1fr);
      border: 1px solid var(--line);
      border-radius: 10px;
      background: var(--panel);
      box-shadow: 0 24px 80px oklch(16% 0.02 250 / 0.28);
      overflow: hidden;
    }

    .series-detail-head {
      position: relative;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 16px 58px 16px 18px;
      border-bottom: 1px solid var(--line);
    }

    .series-detail-title {
      display: flex;
      gap: 14px;
      min-width: 0;
      align-items: center;
    }

    .series-detail-poster {
      width: 58px;
      aspect-ratio: 2 / 3;
      flex: 0 0 auto;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel-2);
      overflow: hidden;
    }

    .series-detail-poster img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .series-detail-title h2 {
      margin: 0;
      font-size: 1.05rem;
      line-height: 1.2;
      letter-spacing: 0;
    }

    .series-detail-meta {
      margin-top: 5px;
      color: var(--muted);
      font-size: 0.82rem;
    }

    .series-detail-close {
      position: absolute;
      top: 14px;
      right: 14px;
      width: 34px;
      height: 34px;
      display: grid;
      place-items: center;
      border: 1px solid oklch(82% 0.014 250);
      border-radius: 8px;
      background: oklch(97.5% 0.007 250);
      color: var(--ink);
      cursor: pointer;
      font: inherit;
      font-size: 1rem;
      line-height: 1;
    }

    .series-detail-close:hover,
    .series-detail-close:focus-visible {
      border-color: var(--focus);
      outline: none;
    }

    .series-detail-body {
      overflow: auto;
      padding: 18px;
      display: grid;
      gap: 16px;
    }

    .detail-facts {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
    }

    .detail-fact {
      display: grid;
      gap: 2px;
      min-height: 58px;
      padding: 9px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel-2);
    }

    .detail-fact span {
      color: var(--muted);
      font-size: 0.72rem;
      font-weight: 650;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .detail-fact strong {
      font-size: 0.9rem;
      line-height: 1.25;
      overflow-wrap: anywhere;
    }

    .detail-synopsis {
      margin: 0;
      color: oklch(35% 0.018 250);
      font-size: 0.9rem;
      line-height: 1.5;
      max-width: 75ch;
    }

    .detail-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }

    .season-detail {
      display: grid;
      gap: 8px;
    }

    .season-detail h3 {
      margin: 0;
      font-size: 0.95rem;
      line-height: 1.25;
      letter-spacing: 0;
    }

    .season-table {
      display: grid;
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }

    .season-row {
      display: grid;
      grid-template-columns: minmax(84px, 1fr) 86px 94px;
      gap: 10px;
      align-items: center;
      min-height: 38px;
      padding: 7px 10px;
      border-top: 1px solid var(--line);
      font-size: 0.84rem;
    }

    .season-row:first-child { border-top: 0; }

    .season-row.header {
      min-height: 34px;
      background: var(--panel-2);
      color: var(--muted);
      font-size: 0.72rem;
      font-weight: 750;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .season-score-empty {
      color: var(--muted);
    }

    body.searching .empty.visible { display: block; }
    body.searching .year-section.empty-year { display: none; }
    .card.hidden { display: none; }

    @media (max-width: 980px) {
      .shell { grid-template-columns: 1fr; }
      .sidebar {
        position: relative;
        height: auto;
        border-right: 0;
        border-bottom: 1px solid var(--line);
      }
      .content { padding: 22px 18px 44px; }
      .toolbar { top: 0; grid-template-columns: 1fr; }
      .meta-line { justify-self: start; }
    }

    @media (max-width: 620px) {
      .decade-years { grid-template-columns: repeat(3, minmax(0, 1fr)); }
      .grid { grid-template-columns: 1fr; }
      .card { grid-template-columns: 78px minmax(0, 1fr); }
      .poster { width: 78px; }
      .title-row { grid-template-columns: 1fr; }
      .rating { justify-self: start; }
      .content { padding-left: 12px; padding-right: 12px; }
      .detail-facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .season-row { grid-template-columns: minmax(80px, 1fr) 72px 74px; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <aside class="sidebar">
      <div class="brand">
        <h1>Series Library</h1>
        <p class="subhead">IMDb-rated genre series with at least 5,000 votes. Filtered by primary origin: US, UK, Canada, Europe, Australia, and New Zealand.</p>
      </div>
      <div class="stats">
        <div class="stat"><strong id="totalCount">0</strong><span>series</span></div>
        <div class="stat"><strong id="yearCount">0</strong><span>years</span></div>
      </div>
      <div class="category-filter" id="categoryFilter" aria-label="Category filter">
        <button type="button" class="category-trigger" id="categoryTrigger" aria-expanded="false" aria-controls="categoryMenu">All categories</button>
        <div class="category-menu" id="categoryMenu">
          <label class="category-option all"><input type="checkbox" id="categoryAll" checked> Select all</label>
          <label class="category-option"><input type="checkbox" class="category-choice" value="Sci-Fi" checked> Sci-Fi</label>
          <label class="category-option"><input type="checkbox" class="category-choice" value="Fantasy" checked> Fantasy</label>
          <label class="category-option"><input type="checkbox" class="category-choice" value="Adventure" checked> Adventure</label>
          <label class="category-option"><input type="checkbox" class="category-choice" value="Animation" checked> Animation</label>
        </div>
      </div>
      <div class="score-filter" aria-label="IMDb score range">
        <div class="score-field">
          <label for="minScore">Min score</label>
          <input id="minScore" type="number" min="1" max="10" step="0.1" inputmode="decimal" placeholder="1.0">
        </div>
        <div class="score-field">
          <label for="maxScore">Max score</label>
          <input id="maxScore" type="number" min="1" max="10" step="0.1" inputmode="decimal" placeholder="10.0">
        </div>
      </div>
      <label class="year-picker" for="yearSelect">
        <span>Jump to year</span>
        <select id="yearSelect"></select>
      </label>
      <div class="nav-label">Browse by decade</div>
      <nav class="year-nav" id="yearNav" aria-label="Jump to year"></nav>
    </aside>
    <main class="content">
      <div class="toolbar">
        <input class="search" id="search" type="search" placeholder="Search titles..." aria-label="Search titles">
        <div class="meta-line" id="metaLine"></div>
      </div>
      <div class="empty" id="empty">No matching series.</div>
      <div id="catalog"></div>
    </main>
  </div>
  <div class="series-detail-backdrop" id="seriesDetailModal" hidden>
    <section class="series-detail-modal" role="dialog" aria-modal="true" aria-labelledby="seriesDetailTitle">
      <header class="series-detail-head" id="seriesDetailHead"></header>
      <div class="series-detail-body" id="seriesDetailBody"></div>
    </section>
  </div>

  <script type="module">
    const response = await fetch("/api/series", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Catalog request failed: ${response.status}`);
    }
    const data = await response.json();
    const byYear = new Map();
    const seriesById = new Map();
    for (const item of data.series) {
      if (!byYear.has(item.year)) byYear.set(item.year, []);
      byYear.get(item.year).push(item);
      seriesById.set(item.id, item);
    }

    const yearNav = document.getElementById("yearNav");
    const yearSelect = document.getElementById("yearSelect");
    const categoryFilter = document.getElementById("categoryFilter");
    const categoryTrigger = document.getElementById("categoryTrigger");
    const categoryAll = document.getElementById("categoryAll");
    const categoryChoices = Array.from(document.querySelectorAll(".category-choice"));
    const minScoreInput = document.getElementById("minScore");
    const maxScoreInput = document.getElementById("maxScore");
    const catalog = document.getElementById("catalog");
    const seriesDetailModal = document.getElementById("seriesDetailModal");
    const seriesDetailHead = document.getElementById("seriesDetailHead");
    const seriesDetailBody = document.getElementById("seriesDetailBody");
    const totalCount = document.getElementById("totalCount");
    const yearCount = document.getElementById("yearCount");
    const metaLine = document.getElementById("metaLine");
    const search = document.getElementById("search");
    const empty = document.getElementById("empty");

    let selectedCategories = new Set(categoryChoices.map(input => input.value));
    let lastSeriesTrigger = null;

    totalCount.textContent = data.total.toLocaleString();
    yearCount.textContent = data.years.length.toLocaleString();
    metaLine.textContent = `Generated ${data.generatedAt}`;

    const formatter = new Intl.NumberFormat();

    function allCategoriesSelected() {
      return selectedCategories.size === categoryChoices.length;
    }

    function updateCategoryTrigger() {
      if (allCategoriesSelected()) {
        categoryTrigger.textContent = "All categories";
        categoryAll.checked = true;
      } else if (selectedCategories.size === 0) {
        categoryTrigger.textContent = "No categories";
        categoryAll.checked = false;
      } else {
        categoryTrigger.textContent = Array.from(selectedCategories).join(", ");
        categoryAll.checked = false;
      }

      for (const input of categoryChoices) {
        input.checked = selectedCategories.has(input.value);
      }
    }

    function escapeText(value) {
      return String(value ?? "");
    }

    function renderPoster(item) {
      if (!item.poster) {
        return `<div class="poster"><div class="poster-fallback">No poster</div></div>`;
      }
      return `<div class="poster"><img loading="lazy" src="${escapeText(item.poster)}" alt="Poster for ${escapeText(item.title)}"></div>`;
    }

    function lerp(start, end, amount) {
      return start + (end - start) * amount;
    }

    function ratingTone(score) {
      const value = Math.max(1, Math.min(10, Number(score) || 1));
      const red = { h: 18, s: 58, l: 28 };
      const yellow = { h: 47, s: 90, l: 58 };
      const green = { h: 134, s: 42, l: 27 };
      const midpoint = 5.5;
      const from = value <= midpoint ? red : yellow;
      const to = value <= midpoint ? yellow : green;
      const t = value <= midpoint ? (value - 1) / (midpoint - 1) : (value - midpoint) / (10 - midpoint);
      const h = lerp(from.h, to.h, t);
      const s = lerp(from.s, to.s, t);
      const l = lerp(from.l, to.l, t);
      const fg = l > 48 ? "oklch(18% 0.018 250)" : "oklch(98% 0.006 250)";
      return `--rating-bg: hsl(${h.toFixed(1)} ${s.toFixed(1)}% ${l.toFixed(1)}%); --rating-fg: ${fg}; --rating-border: hsl(${h.toFixed(1)} ${Math.max(30, s - 14).toFixed(1)}% ${Math.max(20, l - 10).toFixed(1)}%);`;
    }

    const yearsByDecade = new Map();
    function itemMatchesCategory(item) {
      if (item.categories.includes("Animation") && !selectedCategories.has("Animation")) {
        return false;
      }

      const primaryCategories = item.categories.filter(category => category !== "Animation");
      return primaryCategories.some(category => selectedCategories.has(category));
    }

    function getVisibleYearInfo() {
      return data.years
        .map(yearInfo => {
          const count = (byYear.get(yearInfo.year) || []).filter(itemMatchesCategory).length;
          return { year: yearInfo.year, count };
        })
        .filter(yearInfo => yearInfo.count > 0);
    }

    function renderYearNavigation() {
      const visibleYears = getVisibleYearInfo();
      yearNav.textContent = "";
      yearSelect.textContent = "";

      const yearsByDecade = new Map();
      for (const yearInfo of visibleYears) {
        const option = document.createElement("option");
        option.value = String(yearInfo.year);
        option.textContent = `${yearInfo.year} (${yearInfo.count})`;
        yearSelect.appendChild(option);

        const decade = Math.floor(yearInfo.year / 10) * 10;
        if (!yearsByDecade.has(decade)) yearsByDecade.set(decade, []);
        yearsByDecade.get(decade).push(yearInfo);
      }

      for (const [decade, years] of yearsByDecade) {
        const details = document.createElement("details");
        details.className = "decade-group";
        details.dataset.decade = String(decade);
        details.open = decade === Math.floor(visibleYears[0].year / 10) * 10;
        const decadeCount = years.reduce((sum, year) => sum + year.count, 0);
        details.innerHTML = `
          <summary><span>${decade}s</span><span class="decade-count">${decadeCount} series</span></summary>
          <div class="decade-years"></div>
        `;
        const decadeYears = details.querySelector(".decade-years");
        for (const yearInfo of years) {
          const link = document.createElement("a");
          link.href = `#year-${yearInfo.year}`;
          link.dataset.year = String(yearInfo.year);
          link.innerHTML = `<span>${yearInfo.year}</span><small>${yearInfo.count}</small>`;
          decadeYears.appendChild(link);
        }
        yearNav.appendChild(details);
      }

      yearCount.textContent = visibleYears.length.toLocaleString();
    }

    renderYearNavigation();

    /*
    for (const yearInfo of data.years) {
      const option = document.createElement("option");
      option.value = String(yearInfo.year);
      option.textContent = `${yearInfo.year} (${yearInfo.count})`;
      yearSelect.appendChild(option);

      const decade = Math.floor(yearInfo.year / 10) * 10;
      if (!yearsByDecade.has(decade)) yearsByDecade.set(decade, []);
      yearsByDecade.get(decade).push(yearInfo);
    }

    for (const [decade, years] of yearsByDecade) {
      const details = document.createElement("details");
      details.className = "decade-group";
      details.dataset.decade = String(decade);
      details.open = decade === Math.floor(data.years[0].year / 10) * 10;
      const decadeCount = years.reduce((sum, year) => sum + year.count, 0);
      details.innerHTML = `
        <summary><span>${decade}s</span><span class="decade-count">${decadeCount} series</span></summary>
        <div class="decade-years"></div>
      `;
      const decadeYears = details.querySelector(".decade-years");
      for (const yearInfo of years) {
        const link = document.createElement("a");
        link.href = `#year-${yearInfo.year}`;
        link.dataset.year = String(yearInfo.year);
        link.innerHTML = `<span>${yearInfo.year}</span><small>${yearInfo.count}</small>`;
        decadeYears.appendChild(link);
      }
      yearNav.appendChild(details);
    }
    */

    yearSelect.addEventListener("change", () => {
      const target = document.getElementById(`year-${yearSelect.value}`);
      if (target) {
        target.scrollIntoView({ behavior: "auto", block: "start" });
        history.replaceState(null, "", `#year-${yearSelect.value}`);
      }
    });

    for (const [year, items] of byYear) {
      const section = document.createElement("section");
      section.className = "year-section";
      section.id = `year-${year}`;
      section.dataset.year = String(year);
      section.innerHTML = `
        <div class="year-heading">
          <h2>${year}</h2>
          <span>${items.length} series</span>
        </div>
        <div class="grid">
          ${items.map(item => `
            <article class="card" tabindex="0" role="button" aria-label="Open details for ${escapeText(item.title)}" data-id="${escapeText(item.id)}" data-categories="${escapeText(item.categories.join(";"))}" data-search="${escapeText(item.title.toLowerCase())}">
              ${renderPoster(item)}
              <div class="card-main">
                <div class="card-top">
                  <div class="title-row">
                    <h3 class="title">${escapeText(item.title)}</h3>
                    <div class="rating" title="IMDb rating" style="${ratingTone(item.score)}">IMDb ${escapeText(item.score.toFixed(1))}</div>
                  </div>
                  <div class="facts">
                    ${item.categories.map(category => `<span class="fact category-chip">${escapeText(category)}</span>`).join("")}
                    <span class="fact">${escapeText(item.seasonLabel)}</span>
                    <span class="fact">${escapeText(item.years)}</span>
                    <span class="fact">${escapeText(item.primaryOrigin)}</span>
                  </div>
                </div>
                <div class="card-actions">
                  <span class="rank">#${item.rank} in ${item.year}</span>
                  <a class="imdb-link" href="${escapeText(item.imdbUrl)}" target="_blank" rel="noreferrer">IMDb</a>
                </div>
              </div>
            </article>
          `).join("")}
        </div>
      `;
      catalog.appendChild(section);
    }

    const sections = Array.from(document.querySelectorAll(".year-section"));
    let navLinks = Array.from(yearNav.querySelectorAll("a"));
    const observer = new IntersectionObserver(entries => {
      const visible = entries
        .filter(entry => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (!visible) return;
      for (const link of navLinks) {
        link.classList.toggle("active", link.dataset.year === visible.target.dataset.year);
      }
      yearSelect.value = visible.target.dataset.year;
      const activeDecade = Math.floor(Number(visible.target.dataset.year) / 10) * 10;
      for (const decadeGroup of yearNav.querySelectorAll(".decade-group")) {
        decadeGroup.open = decadeGroup.dataset.decade === String(activeDecade);
      }
    }, { rootMargin: "-15% 0px -65% 0px", threshold: [0.01, 0.2, 0.5] });
    sections.forEach(section => observer.observe(section));

    function renderDetailPoster(item) {
      if (!item.poster) {
        return `<div class="series-detail-poster"><div class="poster-fallback">No poster</div></div>`;
      }
      return `<div class="series-detail-poster"><img src="${escapeText(item.poster)}" alt="Poster for ${escapeText(item.title)}"></div>`;
    }

    function renderSeasonDetails(item) {
      const seasons = item.seasonDetails || [];
      if (!seasons.length) {
        return `
          <section class="season-detail">
            <h3>Seasons</h3>
            <p class="update-log-empty">No season details available.</p>
          </section>
        `;
      }

      return `
        <section class="season-detail">
          <h3>Seasons</h3>
          <div class="season-table">
            <div class="season-row header"><span>Season</span><span>Episodes</span><span>IMDb avg</span></div>
            ${seasons.map(season => `
              <div class="season-row">
                <span>${escapeText(season.season ?? "-")}</span>
                <span>${escapeText(season.episodeCount ?? "-")}</span>
                <span class="season-score-empty">${season.score == null ? "Pending" : escapeText(Number(season.score).toFixed(1))}</span>
              </div>
            `).join("")}
          </div>
        </section>
      `;
    }

    function openSeriesDetail(item, trigger) {
      lastSeriesTrigger = trigger || null;
      seriesDetailHead.innerHTML = `
        <div class="series-detail-title">
          ${renderDetailPoster(item)}
          <div>
            <h2 id="seriesDetailTitle">${escapeText(item.title)}</h2>
            <div class="series-detail-meta">${escapeText(item.years)} · ${escapeText(item.primaryOrigin)} · IMDb ${escapeText(Number(item.score).toFixed(1))}</div>
          </div>
        </div>
        <button type="button" class="series-detail-close" id="seriesDetailClose" aria-label="Close series details">×</button>
      `;
      seriesDetailBody.innerHTML = `
        <div class="detail-facts">
          <div class="detail-fact"><span>Seasons</span><strong>${escapeText(item.seasonLabel || item.seasons || "-")}</strong></div>
          <div class="detail-fact"><span>Episodes</span><strong>${escapeText(item.episodes || "-")}</strong></div>
          <div class="detail-fact"><span>Origin</span><strong>${escapeText(item.countries || item.primaryOrigin || "-")}</strong></div>
          <div class="detail-fact"><span>Votes</span><strong>${escapeText(formatter.format(item.votes || 0))}</strong></div>
        </div>
        <p class="detail-synopsis">${escapeText(item.synopsis || "No synopsis available.")}</p>
        <div class="detail-tags">
          ${(item.categories || []).map(category => `<span class="fact category-chip">${escapeText(category)}</span>`).join("")}
          ${(item.genres || []).map(genre => `<span class="fact">${escapeText(genre)}</span>`).join("")}
        </div>
        ${renderSeasonDetails(item)}
      `;
      seriesDetailModal.hidden = false;
      document.getElementById("seriesDetailClose").focus();
    }

    function closeSeriesDetail() {
      seriesDetailModal.hidden = true;
      if (lastSeriesTrigger) lastSeriesTrigger.focus();
    }

    catalog.addEventListener("click", event => {
      if (event.target.closest(".imdb-link")) return;
      const card = event.target.closest(".card");
      if (!card) return;
      const item = seriesById.get(card.dataset.id);
      if (item) openSeriesDetail(item, card);
    });

    catalog.addEventListener("keydown", event => {
      if (event.key !== "Enter") return;
      const card = event.target.closest(".card");
      if (!card) return;
      const item = seriesById.get(card.dataset.id);
      if (item) openSeriesDetail(item, card);
    });

    seriesDetailModal.addEventListener("click", event => {
      if (event.target === seriesDetailModal) closeSeriesDetail();
      if (event.target.id === "seriesDetailClose") closeSeriesDetail();
    });

    function cardMatchesCategory(card) {
      const categories = card.dataset.categories.split(";");
      if (categories.includes("Animation") && !selectedCategories.has("Animation")) {
        return false;
      }

      return categories.filter(category => category !== "Animation").some(category => selectedCategories.has(category));
    }

    function parseScoreInput(input, fallback) {
      if (!input.value.trim()) return fallback;
      const value = Number(input.value);
      if (!Number.isFinite(value)) return fallback;
      return Math.max(1, Math.min(10, Math.round(value * 10) / 10));
    }

    function cardMatchesScore(card) {
      const scoreText = card.querySelector(".rating")?.textContent.replace("IMDb", "").trim();
      const score = Number(scoreText);
      const minScore = parseScoreInput(minScoreInput, 1);
      const maxScore = parseScoreInput(maxScoreInput, 10);
      return score >= Math.min(minScore, maxScore) && score <= Math.max(minScore, maxScore);
    }

    function applyFilters() {
      const query = search.value.trim().toLowerCase();
      const minHasValue = minScoreInput.value.trim().length > 0;
      const maxHasValue = maxScoreInput.value.trim().length > 0;
      const searching = query.length > 0 || !allCategoriesSelected() || minHasValue || maxHasValue;
      document.body.classList.toggle("searching", searching);
      let visibleCards = 0;
      let visibleYears = 0;

      for (const section of sections) {
        let sectionVisible = 0;
        for (const card of section.querySelectorAll(".card")) {
          const match = cardMatchesCategory(card) && cardMatchesScore(card) && (!query || card.dataset.search.includes(query));
          card.classList.toggle("hidden", !match);
          if (match) sectionVisible++;
        }
        section.classList.toggle("empty-year", sectionVisible === 0);
        visibleCards += sectionVisible;
        if (sectionVisible > 0) visibleYears++;
      }

      totalCount.textContent = visibleCards.toLocaleString();
      yearCount.textContent = visibleYears.toLocaleString();
      empty.classList.toggle("visible", searching && visibleCards === 0);
      metaLine.textContent = query || !allCategoriesSelected() || minHasValue || maxHasValue ? `${visibleCards.toLocaleString()} matching series` : `Generated ${data.generatedAt}`;
    }

    function categorySelectionChanged() {
      selectedCategories = new Set(categoryChoices.filter(input => input.checked).map(input => input.value));
      updateCategoryTrigger();
      renderYearNavigation();
      navLinks = Array.from(yearNav.querySelectorAll("a"));
      applyFilters();
    }

    categoryTrigger.addEventListener("click", () => {
      const isOpen = categoryFilter.classList.toggle("open");
      categoryTrigger.setAttribute("aria-expanded", String(isOpen));
    });

    categoryAll.addEventListener("change", () => {
      for (const input of categoryChoices) {
        input.checked = categoryAll.checked;
      }
      categorySelectionChanged();
    });

    for (const input of categoryChoices) {
      input.addEventListener("change", () => {
        categorySelectionChanged();
      });
    }

    document.addEventListener("click", event => {
      if (!categoryFilter.contains(event.target)) {
        categoryFilter.classList.remove("open");
        categoryTrigger.setAttribute("aria-expanded", "false");
      }
    });

    document.addEventListener("keydown", event => {
      if (event.key === "Escape" && !seriesDetailModal.hidden) closeSeriesDetail();
    });

    search.addEventListener("input", () => {
      applyFilters();
    });
    minScoreInput.addEventListener("input", applyFilters);
    maxScoreInput.addEventListener("input", applyFilters);
  </script>
</body>
</html>
'@

$html | Set-Content -Path $OutHtml -Encoding UTF8

Write-Host "Wrote $($items.Count) catalog items to $OutData"
Write-Host "Wrote HTML page to $OutHtml"
