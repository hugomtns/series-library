$ErrorActionPreference = "Stop"

$catalog = Get-Content -Path "imdb_sci_fi_catalog_data.json" -Raw | ConvertFrom-Json
$byId = @{}
foreach ($series in $catalog.series) {
  $byId[$series.id] = $series
}

$since = (Get-Date).Date.AddHours(11).AddMinutes(20)
$changed = foreach ($file in Get-ChildItem -Path "imdb_sci_fi_catalog_cache" -Filter "*.json" | Where-Object { $_.LastWriteTime -gt $since }) {
  $cached = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
  $old = $byId[$cached.id]
  if ($null -eq $old) { continue }

  $numeric = @($cached.seasons | Where-Object { "$($_.season)" -match "^\d+$" })
  $seasonCount = $numeric.Count
  $episodeCount = [int](@($cached.seasons | Measure-Object -Property episodeCount -Sum).Sum)

  if ($seasonCount -ne [int]$old.seasons -or $episodeCount -ne [int]$old.episodes) {
    [pscustomobject]@{
      Title = $old.title
      Year = $old.year
      Tags = ($old.categories -join ", ")
      Seasons = "$($old.seasons) -> $seasonCount"
      Episodes = "$($old.episodes) -> $episodeCount"
      Id = $old.id
    }
  }
}

$changed | Sort-Object Title | Format-Table -AutoSize
"Changed count: $(@($changed).Count)"
