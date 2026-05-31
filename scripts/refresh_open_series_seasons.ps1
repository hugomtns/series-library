param(
  [string]$TitleId = "",
  [int]$Limit = 0
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
  $pageCount = 0

  do {
    $uri = "https://api.imdbapi.dev/titles/$TitleId/episodes"
    if (-not [string]::IsNullOrWhiteSpace($nextPageToken)) {
      $uri = "$uri`?pageToken=$([System.Uri]::EscapeDataString($nextPageToken))"
    }

    $response = Invoke-ImdbApi -Uri $uri
    $episodes += @($response.episodes)
    $nextPageToken = $response.nextPageToken
    $pageCount++
  } while (-not [string]::IsNullOrWhiteSpace($nextPageToken) -and $pageCount -lt 100)

  if ($pageCount -ge 100) {
    throw "Episode pagination exceeded 100 pages for $TitleId."
  }

  return $episodes
}

$root = Resolve-Path "$PSScriptRoot\.."
$dbPath = Join-Path $root "series_library.db"
$cacheDir = Join-Path $root "imdb_sci_fi_catalog_cache"
$env:SERIES_LIBRARY_DB = $dbPath
$seriesJson = & node -e "const Database = require('better-sqlite3'); const db = new Database(process.env.SERIES_LIBRARY_DB, { readonly: true }); const rows = db.prepare('SELECT payload_json FROM series ORDER BY start_year ASC, title ASC').all(); db.close(); const titleId = process.argv[1] || ''; const limit = Number(process.argv[2] || 0); let items = rows.map(row => JSON.parse(row.payload_json)); items = titleId ? items.filter(item => item.id === titleId) : items.filter(item => String(item.years || '').endsWith('-')); if (limit > 0) items = items.slice(0, limit); process.stdout.write(JSON.stringify(items));" $TitleId $Limit
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read series from SQLite."
}
$refreshSeries = @($seriesJson | ConvertFrom-Json)

Write-StepEvent -Current 0 -Total $refreshSeries.Count -Message "Refreshing seasons and episode ratings"
for ($i = 0; $i -lt $refreshSeries.Count; $i++) {
  $item = $refreshSeries[$i]
  Write-StepEvent -Current $i -Total $refreshSeries.Count -Message "Refreshing seasons: $($item.title)"
  $cachePath = Join-Path $cacheDir "$($item.id).json"
  if (Test-Path -Path $cachePath) {
    $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
  } else {
    $cached = [pscustomobject]@{ id = $item.id; detail = $null; seasons = $null; episodes = $null }
  }
  $cached.seasons = @(Get-Seasons -TitleId $item.id)
  $cached | Add-Member -NotePropertyName episodes -NotePropertyValue @(Get-Episodes -TitleId $item.id) -Force
  $now = (Get-Date).ToUniversalTime().ToString("o")
  Set-RefreshValue -Cached $cached -Name "lastSeasonCheckAt" -Value $now
  Set-RefreshValue -Cached $cached -Name "lastEpisodeRatingCheckAt" -Value $now
  $cached | ConvertTo-Json -Depth 20 | Set-Content -Path $cachePath -Encoding UTF8
  Write-StepEvent -Current ($i + 1) -Total $refreshSeries.Count -Message "Finished seasons: $($item.title)"
}

Write-StepEvent -Current $refreshSeries.Count -Total $refreshSeries.Count -Status "complete" -Message "Seasons and episode ratings refreshed"
