$ErrorActionPreference = "Stop"

$allowed = @(
  "US", "GB", "CA", "AU", "NZ",
  "AL", "AD", "AM", "AT", "AZ", "BY", "BE", "BA", "BG", "HR", "CY", "CZ",
  "DK", "EE", "FI", "FR", "GE", "DE", "GR", "HU", "IS", "IE", "IT", "XK",
  "LV", "LI", "LT", "LU", "MT", "MD", "MC", "ME", "NL", "MK", "NO", "PL",
  "PT", "RO", "RU", "SM", "RS", "SK", "SI", "ES", "SE", "CH", "UA",
  "VA"
)

$rows = @(Import-Csv -Path "imdb_sci_fi_series_by_year_all_primary_origin.csv")
$years = @($rows | Group-Object Year)
$badPrimary = @($rows | Where-Object { $allowed -notcontains $_.PrimaryOriginCountryCode })
$badVotes = @($rows | Where-Object { [int]$_.Votes -lt 5000 })
$badYear = @($rows | Where-Object { [int]$_.Year -ne [int]$_.StartYear })
$dupes = @($rows | Group-Object Year, IMDbId | Where-Object { $_.Count -gt 1 })
$excludedJapanExamples = @($rows | Where-Object { $_.Title -match "Dragon Ball|Trigun" })
$maxRowsInYear = ($years | Sort-Object Count -Descending | Select-Object -First 1).Count

[pscustomobject]@{
  Rows = $rows.Count
  Years = $years.Count
  BadPrimaryOrigin = $badPrimary.Count
  BadVotes = $badVotes.Count
  BadYear = $badYear.Count
  DuplicateYearTitle = $dupes.Count
  MaxRowsInYear = $maxRowsInYear
  DragonBallOrTrigunRows = $excludedJapanExamples.Count
  TextOutputExists = (Test-Path -Path "imdb_sci_fi_series_by_year_all_primary_origin.txt")
  CountsOutputExists = (Test-Path -Path "imdb_sci_fi_series_by_year_all_primary_origin.counts.csv")
} | Format-List

if ($badPrimary.Count -gt 0) { throw "Found rows with disallowed primary origin." }
if ($badVotes.Count -gt 0) { throw "Found rows below 5000 votes." }
if ($badYear.Count -gt 0) { throw "Found rows where Year != StartYear." }
if ($dupes.Count -gt 0) { throw "Found duplicate Year+IMDbId rows." }
if ($excludedJapanExamples.Count -gt 0) { throw "Found Dragon Ball or Trigun rows." }
if (-not (Test-Path -Path "imdb_sci_fi_series_by_year_all_primary_origin.txt")) { throw "Missing text output." }
if (-not (Test-Path -Path "imdb_sci_fi_series_by_year_all_primary_origin.counts.csv")) { throw "Missing counts output." }
