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

$root = Resolve-Path "$PSScriptRoot\.."
$dbPath = Join-Path $root "series_library.db"
$cacheDir = Join-Path $root "imdb_sci_fi_catalog_cache"
$env:SERIES_LIBRARY_DB = $dbPath
$openSeriesJson = & node -e "const Database = require('better-sqlite3'); const db = new Database(process.env.SERIES_LIBRARY_DB, { readonly: true }); const rows = db.prepare('SELECT payload_json FROM series ORDER BY start_year ASC, title ASC').all(); db.close(); const items = rows.map(row => JSON.parse(row.payload_json)).filter(item => String(item.years || '').endsWith('-')); process.stdout.write(JSON.stringify(items));"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read open-ended series from SQLite."
}
$openSeries = @($openSeriesJson | ConvertFrom-Json)

Write-StepEvent -Current 0 -Total $openSeries.Count -Message "Refreshing seasons for open-ended series"
for ($i = 0; $i -lt $openSeries.Count; $i++) {
  $item = $openSeries[$i]
  Write-StepEvent -Current $i -Total $openSeries.Count -Message "Refreshing seasons: $($item.title)"
  $cachePath = Join-Path $cacheDir "$($item.id).json"
  if (Test-Path -Path $cachePath) {
    $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
  } else {
    $cached = [pscustomobject]@{ id = $item.id; detail = $null; seasons = $null }
  }
  $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles/$($item.id)/seasons"
  $cached.seasons = @($response.seasons)
  Set-RefreshValue -Cached $cached -Name "lastSeasonCheckAt" -Value (Get-Date).ToUniversalTime().ToString("o")
  $cached | ConvertTo-Json -Depth 20 | Set-Content -Path $cachePath -Encoding UTF8
  Write-StepEvent -Current ($i + 1) -Total $openSeries.Count -Message "Finished seasons: $($item.title)"
}

Write-StepEvent -Current $openSeries.Count -Total $openSeries.Count -Status "complete" -Message "Open-ended seasons refreshed"
