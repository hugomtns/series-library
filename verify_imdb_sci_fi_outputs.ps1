$ErrorActionPreference = "Stop"

$yearDir = "imdb_sci_fi_year_files"
$rankedCsv = "imdb_sci_fi_series_by_year_ranked.csv"
$countsCsv = "imdb_sci_fi_series_by_year_ranked.counts.csv"

$yearFiles = @(Get-ChildItem -Path $yearDir -Filter "imdb_sci_fi_*.csv")
$ranked = @(Import-Csv -Path $rankedCsv)
$counts = @(Import-Csv -Path $countsCsv)

$missingYears = @(1990..2026 | Where-Object {
  -not (Test-Path -Path (Join-Path $yearDir "imdb_sci_fi_$_.csv"))
})

$duplicateRankedKeys = @(
  $ranked |
    Group-Object Year, IMDbId |
    Where-Object { $_.Count -gt 1 }
)

$rankOverflowYears = @(
  $ranked |
    Group-Object Year |
    Where-Object { $_.Count -gt 20 }
)

$invalidVoteRows = @(
  $ranked |
    Where-Object { [int]$_.Votes -lt 5000 }
)

$invalidYearRows = @(
  $ranked |
    Where-Object { [int]$_.Year -ne [int]$_.StartYear }
)

$missingCountryRows = @(
  $ranked |
    Where-Object { [string]::IsNullOrWhiteSpace($_.MatchedAllowedCountryCodes) }
)

$textOutputExists = Test-Path -Path "imdb_sci_fi_series_by_year_ranked.txt"

$summary = [pscustomobject]@{
  YearFileCount = $yearFiles.Count
  RankedRows = $ranked.Count
  CountRows = $counts.Count
  TextOutputExists = $textOutputExists
  MissingYears = ($missingYears -join ",")
  DuplicateRankedKeys = $duplicateRankedKeys.Count
  RankOverflowYears = $rankOverflowYears.Count
  InvalidVoteRows = $invalidVoteRows.Count
  InvalidYearRows = $invalidYearRows.Count
  MissingCountryRows = $missingCountryRows.Count
}

$summary | Format-List

if ($missingYears.Count -gt 0) { throw "Missing year files: $($missingYears -join ', ')" }
if ($duplicateRankedKeys.Count -gt 0) { throw "Duplicate Year+IMDbId keys in ranked output." }
if ($rankOverflowYears.Count -gt 0) { throw "At least one year has more than 20 ranked rows." }
if ($invalidVoteRows.Count -gt 0) { throw "At least one ranked row has fewer than 5000 votes." }
if ($invalidYearRows.Count -gt 0) { throw "At least one ranked row has Year != StartYear." }
if ($missingCountryRows.Count -gt 0) { throw "At least one ranked row did not match an allowed country." }
if (-not $textOutputExists) { throw "Missing text output." }

Write-Host "Top 1990 rows:"
$ranked | Where-Object { $_.Year -eq "1990" } | Select-Object Year,Rank,Title,IMDbScore,Votes | Format-Table -AutoSize

Write-Host "Top 2026 rows:"
$ranked | Where-Object { $_.Year -eq "2026" } | Select-Object Year,Rank,Title,IMDbScore,Votes | Format-Table -AutoSize
