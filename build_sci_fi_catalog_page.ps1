param(
  [string]$SourceCsv = "scripts/.generated/catalog_source.csv",
  [string]$CacheDir = "imdb_sci_fi_catalog_cache",
  [string]$OutData = "scripts/.generated/catalog_data.json",
  [int]$ThrottleMilliseconds = 700,
  [switch]$SkipFetch
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

Write-Host "Wrote $($items.Count) catalog items to $OutData"
