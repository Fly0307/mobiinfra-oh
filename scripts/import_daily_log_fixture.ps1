param(
  [string]$Source = "",
  [string]$BundleName = "com.example.mnnllmchat",
  [string]$ModuleName = "entry",
  [string]$DeviceWorkflowsRoot = "",
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

if ([string]::IsNullOrWhiteSpace($Source)) {
  $Source = Join-Path $PSScriptRoot "..\mock-daily-log\daily-log"
}

if (Test-Path -LiteralPath $Source) {
  $dailyLogChild = Join-Path $Source "daily-log"
  if ((Split-Path -Leaf $Source) -ne "daily-log" -and (Test-Path -LiteralPath $dailyLogChild)) {
    $Source = $dailyLogChild
  }
}

if (-not (Test-Path -LiteralPath $Source)) {
  throw "Daily-log fixture source not found: $Source"
}

$resolvedSource = (Resolve-Path -LiteralPath $Source).Path

if ([string]::IsNullOrWhiteSpace($DeviceWorkflowsRoot)) {
  # Use hdc file send -b <bundle> with the runtime filesDir alias.
  # Direct hdc shell/file access to /data/app/el2/... is usually denied.
  $DeviceWorkflowsRoot = "/data/storage/el2/base/haps/$ModuleName/files/workflows"
}

Write-Host "Using device workflows directory:"
Write-Host "  $DeviceWorkflowsRoot"
Write-Host "Using debug bundle switch:"
Write-Host "  -b $BundleName"
Write-Host "If this path is wrong for your device, override -DeviceWorkflowsRoot, -BundleName, or -ModuleName."

Write-Host "Sending daily-log fixture:"
Write-Host "  from: $resolvedSource"
Write-Host "  to:   $DeviceWorkflowsRoot/daily-log"
Invoke-HdcChecked -Arguments @("file", "send", "-b", $BundleName, $resolvedSource, $DeviceWorkflowsRoot) -FailureMessage "hdc file send failed"

Write-Host "Done. Open the App, go to 数据采集, then tap 同步."
