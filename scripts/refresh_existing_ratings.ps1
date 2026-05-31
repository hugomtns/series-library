$ErrorActionPreference = "Stop"

function Write-StepEvent {
  param(
    [int]$Current,
    [int]$Total,
    [string]$Status = "running",
    [string]$Message = ""
  )

  [pscustomobject]@{
    step = "ratings"
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

$root = Resolve-Path "$PSScriptRoot\.."
$catalogPath = Join-Path $root "imdb_sci_fi_catalog_data.json"
$cacheDir = Join-Path $root "imdb_sci_fi_catalog_cache"
$catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json
$ids = @($catalog.series | ForEach-Object { $_.id } | Sort-Object -Unique)
$batchSize = 5

Write-StepEvent -Current 0 -Total $ids.Count -Message "Refreshing ratings"
for ($i = 0; $i -lt $ids.Count; $i += $batchSize) {
  $chunk = @($ids[$i..([math]::Min($ids.Count - 1, $i + $batchSize - 1))])
  $query = ($chunk | ForEach-Object { "titleIds=$([uri]::EscapeDataString($_))" }) -join "&"
  $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles:batchGet?$query"
  foreach ($detail in @($response.titles)) {
    if (-not $detail.id) { continue }
    $cachePath = Join-Path $cacheDir "$($detail.id).json"
    if (Test-Path -Path $cachePath) {
      $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
    } else {
      $cached = [pscustomobject]@{ id = $detail.id; detail = $null; seasons = $null }
    }
    $cached.detail = $detail
    $cached | ConvertTo-Json -Depth 20 | Set-Content -Path $cachePath -Encoding UTF8
  }
  Write-StepEvent -Current ([math]::Min($ids.Count, $i + $chunk.Count)) -Total $ids.Count -Message "Refreshed $([math]::Min($ids.Count, $i + $chunk.Count)) of $($ids.Count)"
}

Write-StepEvent -Current $ids.Count -Total $ids.Count -Status "complete" -Message "Ratings refreshed"
