param(
  [string]$TitleId = "",
  [int]$Limit = 0,
  [switch]$All,
  [switch]$SkipExisting
)

$ErrorActionPreference = "Stop"

function Write-StepEvent {
  param(
    [int]$Current,
    [int]$Total,
    [string]$Status = "running",
    [string]$Message = ""
  )

  [pscustomobject]@{
    step = "seasons"
    current = $Current
    total = $Total
    status = $Status
    message = $Message
  } | ConvertTo-Json -Compress
}

function Invoke-ImdbApi {
  param([string]$Uri)

  for ($attempt = 1; $attempt -le 6; $attempt++) {
    try {
      $result = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 45
      Start-Sleep -Milliseconds 1200
      return $result
    } catch {
      if ($attempt -eq 6) { throw }
      Start-Sleep -Seconds ([math]::Min(90, 10 * $attempt))
    }
  }
}

function Set-RefreshValue {
  param([object]$Cached, [string]$Name, [string]$Value)

  if ($null -eq $Cached.refresh) {
    $Cached | Add-Member -NotePropertyName refresh -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $Cached.refresh | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-Seasons {
  param([string]$TitleId)

  $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles/$TitleId/seasons"
  return @($response.seasons)
}

function Get-Episodes {
  param([string]$TitleId)

  $episodes = @()
  $nextPageToken = $null
  $totalCount = $null
  $pageCount = 0

  do {
    $uri = "https://api.imdbapi.dev/titles/$TitleId/episodes"
    if (-not [string]::IsNullOrWhiteSpace($nextPageToken)) {
      $uri = "$uri`?pageToken=$([System.Uri]::EscapeDataString($nextPageToken))"
    }

    $response = Invoke-ImdbApi -Uri $uri
    $episodes += @($response.episodes)
    if ($null -ne $response.totalCount) {
      $totalCount = [int]$response.totalCount
    }
    $nextPageToken = $response.nextPageToken
    $pageCount++
  } while (-not [string]::IsNullOrWhiteSpace($nextPageToken) -and $pageCount -lt 100)

  if ($pageCount -ge 100) {
    throw "Episode pagination exceeded 100 pages for $TitleId."
  }

  return [pscustomobject]@{
    episodes = $episodes
    totalCount = $totalCount
  }
}

function Get-ExpectedEpisodeCount {
  param([object[]]$Seasons)

  $total = 0
  foreach ($season in @($Seasons)) {
    $count = 0
    if ([int]::TryParse("$($season.episodeCount)", [ref]$count)) {
      $total += $count
    }
  }
  return $total
}

function Test-HasCompleteEpisodeCache {
  param([object]$Cached)

  $episodeCount = @($Cached.episodes).Count
  if ($episodeCount -eq 0) { return $false }
  if ($null -ne $Cached.episodeTotalCount -and $episodeCount -ge ([int]$Cached.episodeTotalCount - 1)) {
    return $true
  }

  $expectedCount = Get-ExpectedEpisodeCount -Seasons @($Cached.seasons)
  return $expectedCount -gt 0 -and $episodeCount -ge $expectedCount
}

$root = Resolve-Path "$PSScriptRoot\.."
$dbPath = Join-Path $root "series_library.db"
$cacheDir = Join-Path $root "imdb_sci_fi_catalog_cache"
$env:SERIES_LIBRARY_DB = $dbPath
$env:REFRESH_TITLE_ID = $TitleId
$env:REFRESH_LIMIT = "$Limit"
$env:REFRESH_ALL = if ($All) { "1" } else { "0" }
$seriesJson = & node -e "const Database = require('better-sqlite3'); const db = new Database(process.env.SERIES_LIBRARY_DB, { readonly: true }); const rows = db.prepare('SELECT payload_json FROM series ORDER BY start_year ASC, title ASC').all(); db.close(); const titleId = process.env.REFRESH_TITLE_ID || ''; const limit = Number(process.env.REFRESH_LIMIT || 0); const all = process.env.REFRESH_ALL === '1'; let items = rows.map(row => JSON.parse(row.payload_json)); items = titleId ? items.filter(item => item.id === titleId) : all ? items : items.filter(item => String(item.years || '').endsWith('-')); if (limit > 0) items = items.slice(0, limit); process.stdout.write(JSON.stringify(items));"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read series from SQLite."
}
$refreshSeries = $seriesJson | ConvertFrom-Json
$totalSeries = @($refreshSeries | ForEach-Object { $_ }).Count

Write-StepEvent -Current 0 -Total $totalSeries -Message "Refreshing seasons and episode ratings"
$i = 0
foreach ($item in $refreshSeries) {
  Write-StepEvent -Current $i -Total $totalSeries -Message "Refreshing seasons: $($item.title)"
  $cachePath = Join-Path $cacheDir "$($item.id).json"
  if (Test-Path -Path $cachePath) {
    $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
  } else {
    $cached = [pscustomobject]@{ id = $item.id; detail = $null; seasons = $null; episodes = $null }
  }
  if ($SkipExisting -and (Test-HasCompleteEpisodeCache -Cached $cached)) {
    $i++
    Write-StepEvent -Current $i -Total $totalSeries -Message "Skipped cached seasons: $($item.title)"
    continue
  }

  $cached.seasons = @(Get-Seasons -TitleId $item.id)
  $episodeResult = Get-Episodes -TitleId $item.id
  $cached | Add-Member -NotePropertyName episodes -NotePropertyValue @($episodeResult.episodes) -Force
  $cached | Add-Member -NotePropertyName episodeTotalCount -NotePropertyValue $episodeResult.totalCount -Force
  $now = (Get-Date).ToUniversalTime().ToString("o")
  Set-RefreshValue -Cached $cached -Name "lastSeasonCheckAt" -Value $now
  Set-RefreshValue -Cached $cached -Name "lastEpisodeRatingCheckAt" -Value $now
  $cached | ConvertTo-Json -Depth 20 | Set-Content -Path $cachePath -Encoding UTF8
  $i++
  Write-StepEvent -Current $i -Total $totalSeries -Message "Finished seasons: $($item.title)"
}

Write-StepEvent -Current $totalSeries -Total $totalSeries -Status "complete" -Message "Seasons and episode ratings refreshed"
