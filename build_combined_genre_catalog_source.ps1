param(
  [string]$SciFiYearDir = "imdb_sci_fi_year_files_primary_origin",
  [string]$FantasyYearDir = "imdb_fantasy_year_files_primary_origin",
  [string]$AdventureYearDir = "imdb_adventure_year_files_primary_origin",
  [string]$ActionYearDir = "imdb_action_year_files_primary_origin",
  [string]$CacheDir = "imdb_sci_fi_catalog_cache",
  [string]$OutCsv = "scripts/.generated/catalog_source.csv",
  [string]$OutTxt = "scripts/.generated/catalog_source.txt"
)

$ErrorActionPreference = "Stop"

function Add-SourceRows {
  param(
    [System.Collections.Generic.List[object]]$Rows,
    [string]$YearDir,
    [string]$Filter,
    [string]$Category
  )

  Get-ChildItem -Path $YearDir -Filter $Filter |
    Sort-Object Name |
    ForEach-Object {
      foreach ($row in @(Import-Csv -Path $_.FullName)) {
        if (-not $row.IMDbId) {
          continue
        }

        if ($row.PrimaryOriginCountryCode -eq "TR") {
          continue
        }

        $Rows.Add([pscustomobject]@{
          Year = [int]$row.Year
          Title = $row.Title
          IMDbScore = [double]$row.IMDbScore
          Votes = [int]$row.Votes
          StartYear = [int]$row.StartYear
          EndYear = $row.EndYear
          Type = $row.Type
          IMDbId = $row.IMDbId
          IMDbUrl = $row.IMDbUrl
          Category = $Category
          OriginCountryCodes = $row.OriginCountryCodes
          OriginCountries = $row.OriginCountries
          PrimaryOriginCountryCode = $row.PrimaryOriginCountryCode
          MatchedAllowedCountryCodes = $row.MatchedAllowedCountryCodes
        })
      }
    }
}

$sourceRows = New-Object System.Collections.Generic.List[object]
Add-SourceRows -Rows $sourceRows -YearDir $SciFiYearDir -Filter "imdb_sci_fi_primary_origin_*.csv" -Category "Sci-Fi"
Add-SourceRows -Rows $sourceRows -YearDir $FantasyYearDir -Filter "imdb_fantasy_primary_origin_*.csv" -Category "Fantasy"
Add-SourceRows -Rows $sourceRows -YearDir $AdventureYearDir -Filter "imdb_adventure_primary_origin_*.csv" -Category "Adventure"
Add-SourceRows -Rows $sourceRows -YearDir $ActionYearDir -Filter "imdb_action_primary_origin_*.csv" -Category "Action"

function Get-CachedDetail {
  param([string]$IMDbId)

  $cachePath = Join-Path $CacheDir "$IMDbId.json"
  if (-not (Test-Path -Path $cachePath)) {
    return $null
  }

  try {
    return (Get-Content -Path $cachePath -Raw | ConvertFrom-Json).detail
  } catch {
    return $null
  }
}

$combined = foreach ($group in ($sourceRows | Group-Object Year, IMDbId)) {
  $best = $group.Group |
    Sort-Object @{ Expression = "IMDbScore"; Descending = $true },
                @{ Expression = "Votes"; Descending = $true } |
    Select-Object -First 1

  $categories = @($group.Group | ForEach-Object { $_.Category } | Sort-Object -Unique)
  $cachedDetail = Get-CachedDetail -IMDbId $best.IMDbId
  $rating = if ($cachedDetail -and $cachedDetail.rating -and $cachedDetail.rating.aggregateRating) { [double]$cachedDetail.rating.aggregateRating } else { [double]$best.IMDbScore }
  $votes = if ($cachedDetail -and $cachedDetail.rating -and $cachedDetail.rating.voteCount) { [int]$cachedDetail.rating.voteCount } else { [int]$best.Votes }
  $title = if ($cachedDetail -and $cachedDetail.primaryTitle) { $cachedDetail.primaryTitle } else { $best.Title }
  $endYear = if ($cachedDetail -and $null -ne $cachedDetail.endYear) { $cachedDetail.endYear } else { $best.EndYear }

  [pscustomobject]@{
    Year = [int]$best.Year
    Rank = 0
    Title = $title
    IMDbScore = $rating
    Votes = $votes
    StartYear = [int]$best.StartYear
    EndYear = $endYear
    Type = $best.Type
    IMDbId = $best.IMDbId
    IMDbUrl = $best.IMDbUrl
    Categories = ($categories -join ";")
    OriginCountryCodes = $best.OriginCountryCodes
    OriginCountries = $best.OriginCountries
    PrimaryOriginCountryCode = $best.PrimaryOriginCountryCode
    MatchedAllowedCountryCodes = $best.MatchedAllowedCountryCodes
  }
}

$ranked = foreach ($yearGroup in ($combined | Group-Object Year | Sort-Object { [int]$_.Name })) {
  $rank = 1
  $yearGroup.Group |
    Sort-Object @{ Expression = "IMDbScore"; Descending = $true },
                @{ Expression = "Votes"; Descending = $true },
                @{ Expression = "Title"; Descending = $false } |
    ForEach-Object {
      $_.Rank = $rank
      $rank++
      $_
    }
}

$outCsvDir = [io.path]::GetDirectoryName($OutCsv)
if (-not [string]::IsNullOrWhiteSpace($outCsvDir)) {
  New-Item -ItemType Directory -Path $outCsvDir -Force | Out-Null
}
$outTxtDir = [io.path]::GetDirectoryName($OutTxt)
if (-not [string]::IsNullOrWhiteSpace($outTxtDir)) {
  New-Item -ItemType Directory -Path $outTxtDir -Force | Out-Null
}
$ranked | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

$countsPath = [io.path]::ChangeExtension($OutCsv, ".counts.csv")
$ranked |
  Group-Object Year |
  Sort-Object { [int]$_.Name } |
  ForEach-Object {
    [pscustomobject]@{
      Year = [int]$_.Name
      EligibleTitles = $_.Count
      SciFiTitles = @($_.Group | Where-Object { $_.Categories -match "(^|;)Sci-Fi(;|$)" }).Count
      FantasyTitles = @($_.Group | Where-Object { $_.Categories -match "(^|;)Fantasy(;|$)" }).Count
      AdventureTitles = @($_.Group | Where-Object { $_.Categories -match "(^|;)Adventure(;|$)" }).Count
      ActionTitles = @($_.Group | Where-Object { $_.Categories -match "(^|;)Action(;|$)" }).Count
      BothTitles = @($_.Group | Where-Object { $_.Categories -match "(^|;)Sci-Fi(;|$)" -and $_.Categories -match "(^|;)Fantasy(;|$)" }).Count
    }
  } |
  Export-Csv -Path $countsPath -NoTypeInformation -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
foreach ($yearGroup in ($ranked | Group-Object Year | Sort-Object { [int]$_.Name })) {
  $lines.Add("Year: $($yearGroup.Name)")
  foreach ($row in ($yearGroup.Group | Sort-Object { [int]$_.Rank })) {
    $lines.Add(("#{0}: {1} | {2} | IMDb Score (full series): {3:N1} | Votes: {4} | IMDb: {5}" -f $row.Rank, $row.Title, $row.Categories, [double]$row.IMDbScore, [int]$row.Votes, $row.IMDbUrl))
  }
  $lines.Add("")
}
$lines | Set-Content -Path $OutTxt -Encoding UTF8

Write-Host "Wrote $($ranked.Count) combined rows to $OutCsv"
Write-Host "Wrote counts to $countsPath"
Write-Host "Wrote text output to $OutTxt"
