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

Write-StepEvent -Current 0 -Total 4 -Message "Combining genre sources"
& "$root\build_combined_genre_catalog_source.ps1" -OutCsv $sourceCsv -OutTxt $sourceTxt

Write-StepEvent -Current 1 -Total 4 -Message "Rebuilding catalog JSON"
& "$root\build_sci_fi_catalog_page.ps1" -SourceCsv $sourceCsv -OutData $catalogJson

Write-StepEvent -Current 2 -Total 4 -Message "Migrating to SQLite"
& node "$root\scripts\migrate_to_sqlite.js" --input $catalogJson
if ($LASTEXITCODE -ne 0) {
  throw "SQLite migration failed."
}

Write-StepEvent -Current 3 -Total 4 -Message "Exporting public catalog"
& node "$root\scripts\export_public_catalog.js"
if ($LASTEXITCODE -ne 0) {
  throw "Public catalog export failed."
}

Write-StepEvent -Current 4 -Total 4 -Status "complete" -Message "Database rebuilt"
