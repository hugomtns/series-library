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

Write-StepEvent -Current 0 -Total 3 -Message "Combining genre sources"
& "$root\build_combined_genre_catalog_source.ps1"

Write-StepEvent -Current 1 -Total 3 -Message "Rebuilding catalog JSON"
& "$root\build_sci_fi_catalog_page.ps1" -SkipHtml

Write-StepEvent -Current 2 -Total 3 -Message "Migrating to SQLite"
& node "$root\scripts\migrate_to_sqlite.js"

Write-StepEvent -Current 3 -Total 3 -Status "complete" -Message "Database rebuilt"
