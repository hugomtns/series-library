param(
  [string]$TitleId = "",
  [string]$Category = "",
  [int]$Limit = 0,
  [switch]$All,
  [switch]$SkipExisting,
  [int]$Concurrency = 1
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
  } while (-not [string]::IsNullOrWhiteSpace($nextPageToken) -and $pageCount -lt 500)

  if ($pageCount -ge 500) {
    throw "Episode pagination exceeded 500 pages for $TitleId."
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

function Start-SeriesRefreshJob {
  param(
    [string]$ScriptPath,
    [string]$RefreshTitleId,
    [bool]$ShouldSkipExisting
  )

  Start-Job -ArgumentList $ScriptPath, $RefreshTitleId, $ShouldSkipExisting -ScriptBlock {
    param($ScriptPath, $RefreshTitleId, $ShouldSkipExisting)

    $arguments = @(
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $ScriptPath,
      "-TitleId",
      $RefreshTitleId,
      "-Concurrency",
      "1"
    )
    if ($ShouldSkipExisting) {
      $arguments += "-SkipExisting"
    }

    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Season refresh failed for $RefreshTitleId."
    }
  }
}

$root = Resolve-Path "$PSScriptRoot\.."
Set-Location $root
$dbPath = Join-Path $root "series_library.db"
$cacheDir = Join-Path $root "imdb_sci_fi_catalog_cache"
$env:SERIES_LIBRARY_DB = $dbPath
$env:REFRESH_TITLE_ID = $TitleId
$env:REFRESH_CATEGORY = $Category
$env:REFRESH_LIMIT = "$Limit"
$env:REFRESH_ALL = if ($All) { "1" } else { "0" }
$env:REFRESH_SKIP_EXISTING = if ($SkipExisting) { "1" } else { "0" }
$selectorArgs = @("scripts/season_cache_health.js", "--select-refresh")
if (-not [string]::IsNullOrWhiteSpace($TitleId)) { $selectorArgs += @("--title-id", $TitleId) }
if (-not [string]::IsNullOrWhiteSpace($Category)) { $selectorArgs += @("--category", $Category) }
if ($Limit -gt 0) { $selectorArgs += @("--limit", "$Limit") }
if ($All) { $selectorArgs += "--all" }
if ($SkipExisting) { $selectorArgs += "--skip-existing" }
$seriesJson = & node @selectorArgs
if ($LASTEXITCODE -ne 0) {
  throw "Failed to read series from SQLite."
}
$refreshSeries = $seriesJson | ConvertFrom-Json
$totalSeries = @($refreshSeries | ForEach-Object { $_ }).Count

Write-StepEvent -Current 0 -Total $totalSeries -Message "Refreshing seasons and episode ratings"

if ($Concurrency -gt 1 -and [string]::IsNullOrWhiteSpace($TitleId) -and $totalSeries -gt 1) {
  $scriptPath = $PSCommandPath
  $pending = New-Object System.Collections.Queue
  foreach ($item in @($refreshSeries)) {
    [void]$pending.Enqueue($item)
  }

  $activeJobs = @()
  $completedJobs = 0
  while ($pending.Count -gt 0 -and $activeJobs.Count -lt $Concurrency) {
    $nextItem = $pending.Dequeue()
    Write-StepEvent -Current $completedJobs -Total $totalSeries -Message "Queued seasons: $($nextItem.title)"
    $activeJobs += Start-SeriesRefreshJob -ScriptPath $scriptPath -RefreshTitleId $nextItem.id -ShouldSkipExisting $SkipExisting.IsPresent
  }

  while ($activeJobs.Count -gt 0) {
    $finishedJob = Wait-Job -Job $activeJobs -Any
    $jobOutput = Receive-Job -Job $finishedJob
    if ($finishedJob.State -ne "Completed") {
      Remove-Job -Job $finishedJob -Force
      throw (($jobOutput | Out-String).Trim())
    }

    Remove-Job -Job $finishedJob
    $activeJobs = @($activeJobs | Where-Object { $_.Id -ne $finishedJob.Id })
    $completedJobs++
    Write-StepEvent -Current $completedJobs -Total $totalSeries -Message "Finished queued season refresh $completedJobs of $totalSeries"

    while ($pending.Count -gt 0 -and $activeJobs.Count -lt $Concurrency) {
      $nextItem = $pending.Dequeue()
      Write-StepEvent -Current $completedJobs -Total $totalSeries -Message "Queued seasons: $($nextItem.title)"
      $activeJobs += Start-SeriesRefreshJob -ScriptPath $scriptPath -RefreshTitleId $nextItem.id -ShouldSkipExisting $SkipExisting.IsPresent
    }
  }

  Write-StepEvent -Current $totalSeries -Total $totalSeries -Status "complete" -Message "Seasons and episode ratings refreshed"
  return
}

$i = 0
foreach ($item in $refreshSeries) {
  Write-StepEvent -Current $i -Total $totalSeries -Message "Refreshing seasons: $($item.title)"
  $cachePath = Join-Path $cacheDir "$($item.id).json"
  if (Test-Path -Path $cachePath) {
    $cached = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
  } else {
    $cached = [pscustomobject]@{ id = $item.id; detail = $null; seasons = $null; episodes = $null }
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
