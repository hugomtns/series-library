param(
  [int]$StartYear = (Get-Date).Year,
  [int]$EndYear = (Get-Date).Year,
  [int]$MaxVoteCount = 4999
)

$ErrorActionPreference = "Stop"

$genres = @("Sci-Fi", "Fantasy", "Adventure")
$allowedPrimary = New-Object System.Collections.Generic.HashSet[string]
@("US", "GB", "CA") | ForEach-Object { [void]$allowedPrimary.Add($_) }

function Invoke-ImdbApi {
  param([string]$Uri)
  $result = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 45
  Start-Sleep -Milliseconds 700
  return $result
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
    $details += @($response.titles)
  }
  return $details
}

$candidateRows = foreach ($year in $StartYear..$EndYear) {
  foreach ($genre in $genres) {
    Get-Candidates -Genre $genre -Year $year
  }
}

$groups = $candidateRows | Group-Object Id
$ids = @($groups | ForEach-Object { $_.Name } | Sort-Object -Unique)
$detailsById = @{}
foreach ($detail in Get-Details -Ids $ids) {
  $detailsById[$detail.id] = $detail
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

$results | Sort-Object @{ Expression = "Votes"; Descending = $true }, @{ Expression = "Score"; Descending = $true } | Format-Table -AutoSize
