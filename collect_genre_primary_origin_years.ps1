param(
  [string]$Genre = "Fantasy",
  [string]$GenreLabel = "Fantasy",
  [string]$FilePrefix = "imdb_fantasy_primary_origin",
  [int]$StartYear = 1960,
  [int]$EndYear = (Get-Date).Year,
  [string]$OutYearDir = "imdb_fantasy_year_files_primary_origin",
  [int]$ThrottleMilliseconds = 1200,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$allowedCountryCodesArray = @(
  "US", "GB", "CA", "AU", "NZ",
  "AL", "AD", "AM", "AT", "AZ", "BY", "BE", "BA", "BG", "HR", "CY", "CZ",
  "DK", "EE", "FI", "FR", "GE", "DE", "GR", "HU", "IS", "IE", "IT", "XK",
  "LV", "LI", "LT", "LU", "MT", "MD", "MC", "ME", "NL", "MK", "NO", "PL",
  "PT", "RO", "RU", "SM", "RS", "SK", "SI", "ES", "SE", "CH", "UA",
  "VA"
)

$allowedCountryCodes = New-Object System.Collections.Generic.HashSet[string]
foreach ($countryCode in $allowedCountryCodesArray) {
  [void]$allowedCountryCodes.Add($countryCode)
}

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

function Get-ImdbYearCandidates {
  param([int]$Year)

  $titles = New-Object System.Collections.Generic.List[object]
  $pageToken = $null
  $encodedGenre = [uri]::EscapeDataString($Genre)

  do {
    $uri = "https://api.imdbapi.dev/titles?types=TV_SERIES&types=TV_MINI_SERIES&genres=$encodedGenre&startYear=$Year&endYear=$Year&minVoteCount=5000&sortBy=SORT_BY_USER_RATING&sortOrder=DESC"
    if ($pageToken) {
      $uri += "&pageToken=$([uri]::EscapeDataString($pageToken))"
    }

    $response = Invoke-ImdbApi -Uri $uri
    foreach ($title in @($response.titles)) {
      if ($title.id) {
        $titles.Add($title)
      }
    }

    $pageToken = $response.nextPageToken
  } while ($pageToken)

  return $titles
}

function Get-ImdbTitleDetails {
  param([string[]]$TitleIds)

  $titles = New-Object System.Collections.Generic.List[object]
  if ($TitleIds.Count -eq 0) {
    return $titles
  }

  for ($i = 0; $i -lt $TitleIds.Count; $i += 5) {
    $chunkSize = [math]::Min(5, $TitleIds.Count - $i)
    $chunk = $TitleIds[$i..($i + $chunkSize - 1)]
    $query = ($chunk | ForEach-Object { "titleIds=$([uri]::EscapeDataString($_))" }) -join "&"
    $response = Invoke-ImdbApi -Uri "https://api.imdbapi.dev/titles:batchGet?$query"

    foreach ($title in @($response.titles)) {
      $titles.Add($title)
    }
  }

  return $titles
}

function Convert-ToPrimaryOriginRow {
  param(
    [object]$Title,
    [int]$Year
  )

  if (-not $Title.rating -or [int]$Title.rating.voteCount -lt 5000) {
    return $null
  }

  if ([int]$Title.startYear -ne $Year) {
    return $null
  }

  $genres = @($Title.genres)
  if ($genres -notcontains $Genre) {
    return $null
  }

  $originCodes = @($Title.originCountries | ForEach-Object { $_.code })
  $originNames = @($Title.originCountries | ForEach-Object { $_.name })
  if ($originCodes.Count -eq 0) {
    return $null
  }

  $primaryOriginCode = $originCodes[0]
  if (-not $allowedCountryCodes.Contains($primaryOriginCode)) {
    return $null
  }

  $allowedMatches = @($originCodes | Where-Object { $allowedCountryCodes.Contains($_) })

  return [pscustomobject]@{
    Year = [int]$Title.startYear
    Rank = 0
    Title = $Title.primaryTitle
    IMDbScore = [double]$Title.rating.aggregateRating
    Votes = [int]$Title.rating.voteCount
    StartYear = [int]$Title.startYear
    EndYear = $Title.endYear
    Type = $Title.type
    IMDbId = $Title.id
    IMDbUrl = "https://www.imdb.com/title/$($Title.id)/"
    Categories = $GenreLabel
    OriginCountryCodes = ($originCodes -join ";")
    OriginCountries = ($originNames -join ";")
    PrimaryOriginCountryCode = $primaryOriginCode
    MatchedAllowedCountryCodes = (($allowedMatches | Sort-Object -Unique) -join ";")
  }
}

New-Item -ItemType Directory -Path $OutYearDir -Force | Out-Null

foreach ($year in $StartYear..$EndYear) {
  $yearCsv = Join-Path $OutYearDir "$FilePrefix`_$year.csv"
  $yearJson = Join-Path $OutYearDir "$FilePrefix`_$year.json"

  if ((Test-Path -Path $yearCsv) -and -not $Force) {
    Write-Host "Skipping $year; $yearCsv already exists."
    continue
  }

  Write-Host "Collecting $GenreLabel $year..."
  $candidates = Get-ImdbYearCandidates -Year $year
  $candidateIds = @($candidates | ForEach-Object { $_.id } | Sort-Object -Unique)
  $details = Get-ImdbTitleDetails -TitleIds $candidateIds
  $rows = New-Object System.Collections.Generic.List[object]

  foreach ($title in @($details)) {
    $row = Convert-ToPrimaryOriginRow -Title $title -Year $year
    if ($row) {
      $rows.Add($row)
    }
  }

  $rank = 1
  $sortedRows = @(
    $rows |
      Sort-Object @{ Expression = "IMDbScore"; Descending = $true },
                  @{ Expression = "Votes"; Descending = $true },
                  @{ Expression = "Title"; Descending = $false } |
      ForEach-Object {
        $_.Rank = $rank
        $rank++
        $_
      }
  )

  $sortedRows | Export-Csv -Path $yearCsv -NoTypeInformation -Encoding UTF8
  $sortedRows | ConvertTo-Json -Depth 8 | Set-Content -Path $yearJson -Encoding UTF8
  Write-Host "Wrote $($sortedRows.Count) $GenreLabel rows for $year."
}
