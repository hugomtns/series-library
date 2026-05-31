param(
  [int]$StartYear = (Get-Date).Year,
  [int]$EndYear = (Get-Date).Year,
  [int]$MaxVoteCount = 4999,
  [string]$OutJson = "scripts/.generated/under_5k_near_misses.json",
  [string]$OutCsv = "scripts/.generated/under_5k_near_misses.csv",
  [switch]$Table,
  [switch]$NonBlocking
)

$ErrorActionPreference = "Stop"

$genres = @("Sci-Fi", "Fantasy", "Adventure")
$allowedPrimary = New-Object System.Collections.Generic.HashSet[string]
@("US", "GB", "CA") | ForEach-Object { [void]$allowedPrimary.Add($_) }

function Write-StepEvent {
  param(
    [int]$Current,
    [int]$Total,
    [string]$Status = "running",
    [string]$Message = ""
  )

  [pscustomobject]@{
    step = "nearMisses"
    current = $Current
    total = $Total
    status = $Status
    message = $Message
  } | ConvertTo-Json -Compress
}

function Invoke-ImdbApi {
  param([string]$Uri)
  $maxAttempts = if ($NonBlocking) { 1 } else { 4 }
  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
      $result = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 45
      Start-Sleep -Milliseconds 900
      return $result
    } catch {
      if ($attempt -eq $maxAttempts) {
        if ($NonBlocking) { return $null }
        throw
      }
      Start-Sleep -Seconds ([math]::Min(60, 10 * $attempt))
    }
  }
}

function Get-Candidates {
  param([string]$Genre, [int]$Year)

  $pageToken = $null
  do {
    $encodedGenre = [uri]::EscapeDataString($Genre)
    $uri = "https://api.imdbapi.dev/titles?types=TV_SERIES&types=TV_MINI_SERIES&genres=$encodedGenre&startYear=$Year&endYear=$Year&maxVoteCount=$MaxVoteCount&sortBy=SORT_BY_USER_RATING&sortOrder=DESC"
    if ($pageToken) {
      $uri += "&pageToken=$([uri]::EscapeDataString($pageToken))"
    }
    $response = Invoke-ImdbApi -Uri $uri
    if ($null -eq $response) { return }
    foreach ($title in @($response.titles)) {
      if ($title.id -and $title.rating.voteCount -gt 0 -and $title.rating.voteCount -le $MaxVoteCount) {
        [pscustomobject]@{
          Id = $title.id
          Genre = $Genre
          Year = $Year
          Title = $title.primaryTitle
          Score = $title.rating.aggregateRating
          Votes = $title.rating.voteCount
        }
      }
    }
    $pageToken = $response.nextPageToken
  } while ($pageToken)
}

function Get-Details {
  param([string[]]$Ids)

  $details = @()
  for ($i = 0; $i -lt $Ids.Count; $i += 5) {
    $chunk = @($Ids[$i..([math]::Min($Ids.Count - 1, $i + 4))])
    $query = ($chunk | ForEach-Object { "titleIds=$([uri]::EscapeDataString($_))" }) -join "&"
    $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles:batchGet?$query"
    if ($null -eq $response) { continue }
    $details += @($response.titles)
  }
  return $details
}

$totalSearches = (($EndYear - $StartYear) + 1) * $genres.Count
$searchIndex = 0
Write-StepEvent -Current 0 -Total $totalSearches -Message "Finding under-5k near misses"

$candidateRows = foreach ($year in $StartYear..$EndYear) {
  foreach ($genre in $genres) {
    Write-StepEvent -Current $searchIndex -Total $totalSearches -Message "Searching $genre $year"
    Get-Candidates -Genre $genre -Year $year
    $searchIndex++
  }
}
Write-StepEvent -Current $totalSearches -Total $totalSearches -Message "Fetching details for near misses"

$groups = $candidateRows | Group-Object Id
$ids = @($groups | ForEach-Object { $_.Name } | Where-Object { $_ -match "^tt\d+$" } | Sort-Object -Unique)
$detailsById = @{}
if ($ids.Count -gt 0) {
  foreach ($detail in Get-Details -Ids $ids) {
    $detailsById[$detail.id] = $detail
  }
}

$results = foreach ($group in $groups) {
  $detail = $detailsById[$group.Name]
  if ($null -eq $detail -or $null -eq $detail.originCountries -or $detail.originCountries.Count -eq 0) { continue }
  $primaryOrigin = $detail.originCountries[0].code
  if (-not $allowedPrimary.Contains($primaryOrigin)) { continue }

  [pscustomobject]@{
    Title = $detail.primaryTitle
    Year = $detail.startYear
    Score = $detail.rating.aggregateRating
    Votes = $detail.rating.voteCount
    Tags = (@($group.Group.Genre) | Sort-Object -Unique) -join ", "
    Genres = (@($detail.genres) | Sort-Object -Unique) -join ", "
    PrimaryOrigin = $primaryOrigin
    Id = $detail.id
    Url = "https://www.imdb.com/title/$($detail.id)/"
  }
}

$sorted = @($results | Sort-Object @{ Expression = "Votes"; Descending = $true }, @{ Expression = "Score"; Descending = $true })

$report = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  startYear = $StartYear
  endYear = $EndYear
  maxVoteCount = $MaxVoteCount
  primaryOrigins = @("US", "GB", "CA")
  total = $sorted.Count
  series = $sorted
}

$outJsonDir = [io.path]::GetDirectoryName($OutJson)
if (-not [string]::IsNullOrWhiteSpace($outJsonDir)) {
  New-Item -ItemType Directory -Path $outJsonDir -Force | Out-Null
}
$outCsvDir = [io.path]::GetDirectoryName($OutCsv)
if (-not [string]::IsNullOrWhiteSpace($outCsvDir)) {
  New-Item -ItemType Directory -Path $outCsvDir -Force | Out-Null
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutJson -Encoding UTF8
$sorted | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

Write-StepEvent -Current $totalSearches -Total $totalSearches -Status "complete" -Message "Found $($sorted.Count) under-5k near misses"

if ($Table) {
  $sorted | Format-Table -AutoSize
}
