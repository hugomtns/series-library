$ErrorActionPreference = "Stop"

function Write-StepEvent {
  param(
    [int]$Current,
    [int]$Total,
    [string]$Status = "running",
    [string]$Message = ""
  )

  [pscustomobject]@{
    step = "rebuild"
    current = $Current
    total = $Total
    status = $Status
    message = $Message
  } | ConvertTo-Json -Compress
}

$root = Resolve-Path "$PSScriptRoot\.."
$generatedDir = Join-Path $root "scripts\.generated"
$sourceCsv = Join-Path $generatedDir "catalog_source.csv"
$sourceTxt = Join-Path $generatedDir "catalog_source.txt"
$catalogJson = Join-Path $generatedDir "catalog_data.json"

New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null

Write-StepEvent -Current 0 -Total 3 -Message "Combining genre sources"
& "$root\build_combined_genre_catalog_source.ps1" -OutCsv $sourceCsv -OutTxt $sourceTxt

Write-StepEvent -Current 1 -Total 3 -Message "Rebuilding catalog JSON"
& "$root\build_sci_fi_catalog_page.ps1" -SourceCsv $sourceCsv -OutData $catalogJson -SkipHtml

Write-StepEvent -Current 2 -Total 3 -Message "Migrating to SQLite"
& node "$root\scripts\migrate_to_sqlite.js" --input $catalogJson

Write-StepEvent -Current 3 -Total 3 -Status "complete" -Message "Database rebuilt"
