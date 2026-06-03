param(
  [string]$BundleName = "com.example.mnnllmchat",
  [string]$ModuleName = "entry",
  [string]$DeviceWorkflowsRoot = "",
  [string]$OutputRoot = "exports",
  [string]$Hdc = "hdc"
)

$ErrorActionPreference = "Stop"

function Invoke-HdcChecked {
  param(
    [string[]]$Arguments,
    [string]$FailureMessage
  )

  $output = & $Hdc @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($output) {
    $output | ForEach-Object { Write-Host $_ }
  }
  $text = ($output | Out-String)
  if ($exitCode -ne 0 -or $text -match "\[Fail\]|Permission denied|No such file|not found") {
    throw "$FailureMessage`n$text"
  }
}

if ([string]::IsNullOrWhiteSpace($DeviceWorkflowsRoot)) {
  $DeviceWorkflowsRoot = "/data/storage/el2/base/haps/$ModuleName/files/workflows"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resolvedOutputRoot = Join-Path (Get-Location).Path $OutputRoot
$destination = Join-Path $resolvedOutputRoot "workflows-$timestamp"

New-Item -ItemType Directory -Force -Path $destination | Out-Null

Write-Host "Exporting device workflows:"
Write-Host "  bundle: $BundleName"
Write-Host "  from:   $DeviceWorkflowsRoot"
Write-Host "  to:     $destination"

Invoke-HdcChecked -Arguments @("file", "recv", "-b", $BundleName, $DeviceWorkflowsRoot, $destination) -FailureMessage "hdc file recv failed"

Write-Host "Done. Exported files are under:"
Write-Host "  $destination"
