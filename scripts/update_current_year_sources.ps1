$ErrorActionPreference = "Stop"

function Write-StepEvent {
  param(
    [int]$Current,
    [int]$Total,
    [string]$Status = "running",
    [string]$Message = ""
  )

  [pscustomobject]@{
    step = "newSeries"
    current = $Current
    total = $Total
    status = $Status
    message = $Message
  } | ConvertTo-Json -Compress
}

$year = (Get-Date).Year
$tasks = @(
  @{ Genre = "Sci-Fi"; GenreLabel = "Sci-Fi"; FilePrefix = "imdb_sci_fi_primary_origin"; OutYearDir = "imdb_sci_fi_year_files_primary_origin" },
  @{ Genre = "Fantasy"; GenreLabel = "Fantasy"; FilePrefix = "imdb_fantasy_primary_origin"; OutYearDir = "imdb_fantasy_year_files_primary_origin" },
  @{ Genre = "Adventure"; GenreLabel = "Adventure"; FilePrefix = "imdb_adventure_primary_origin"; OutYearDir = "imdb_adventure_year_files_primary_origin" }
)

Write-StepEvent -Current 0 -Total $tasks.Count -Message "Refreshing $year searches"
for ($i = 0; $i -lt $tasks.Count; $i++) {
  $task = $tasks[$i]
  Write-StepEvent -Current $i -Total $tasks.Count -Message "Refreshing $($task.GenreLabel) $year"
  & "$PSScriptRoot\..\collect_genre_primary_origin_years.ps1" `
    -Genre $task.Genre `
    -GenreLabel $task.GenreLabel `
    -FilePrefix $task.FilePrefix `
    -OutYearDir $task.OutYearDir `
    -StartYear $year `
    -EndYear $year `
    -Force
  Write-StepEvent -Current ($i + 1) -Total $tasks.Count -Message "Finished $($task.GenreLabel) $year"
}

Write-StepEvent -Current $tasks.Count -Total $tasks.Count -Status "complete" -Message "Current-year searches refreshed"
