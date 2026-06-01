function Get-TextOrEmpty($Path) {
  if (Test-Path -Path $Path) {
    return Get-Content -Path $Path -Raw
  }
  return ""
}

function Get-DetailRows($detailsPayload) {
  if ($null -eq $detailsPayload -or $null -eq $detailsPayload.series) { return @() }
  if ($detailsPayload.series -is [array]) { return @($detailsPayload.series) }
  return @($detailsPayload.series.PSObject.Properties | ForEach-Object { $_.Value })
}

function Test-ContainsAll($text, [string[]]$patterns) {
  foreach ($pattern in $patterns) {
    if (-not $text.Contains($pattern)) { return $false }
  }
  return $true
}

function Assert-Condition($condition, $message) {
  if (-not $condition) { throw $message }
}
