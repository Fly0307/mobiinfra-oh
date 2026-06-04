param(
  [string]$BundleName = "com.example.mnnllmchat",
  [string]$ModuleName = "entry",
  [string]$DeviceFilesRoot = "",
  [string]$Hdc = "hdc",
  [switch]$Force,
  [switch]$NoRestartApp,
  [switch]$FullAppData
)

$ErrorActionPreference = "Stop"

function Invoke-HdcChecked {
  param(
    [string[]]$Arguments,
    [string]$FailureMessage,
    [switch]$AllowNoOutput
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

if (-not $Force) {
  Write-Host "This will clear workflows test data for bundle: $BundleName"
  Write-Host "Targeted mode clears daily-log, consolidated outputs, indexes, profile, and runs after the App processes the clear marker."
  Write-Host "It does not clear model files or other App data."
  if ($FullAppData) {
    Write-Host "FullAppData mode will clear ALL app data and cache for the bundle."
  }
  $answer = Read-Host "Type CLEAR to continue"
  if ($answer -ne "CLEAR") {
    Write-Host "Canceled."
    exit 0
  }
}

if ($FullAppData) {
  Write-Host "Clearing all app data via bm clean:"
  Write-Host "  bundle: $BundleName"
  Invoke-HdcChecked -Arguments @("shell", "bm clean -n $BundleName -c -d") -FailureMessage "bm clean failed"
  Write-Host "Done. All app data/cache for $BundleName was cleared."
  exit 0
}

if ([string]::IsNullOrWhiteSpace($DeviceFilesRoot)) {
  $DeviceFilesRoot = "/data/storage/el2/base/haps/$ModuleName/files"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mobiinfra-clear-workflows-" + [Guid]::NewGuid().ToString("N"))
$localWorkflows = Join-Path $tempRoot "workflows"
$markerPath = Join-Path $localWorkflows ".clear-workflows-request.json"

try {
  New-Item -ItemType Directory -Force -Path $localWorkflows | Out-Null
  $marker = @{
    requested_at = (Get-Date).ToString("o")
    reason = "clear workflows for repeat fixture validation"
  } | ConvertTo-Json -Depth 3
  Set-Content -LiteralPath $markerPath -Value $marker -Encoding UTF8

  Write-Host "Sending workflows clear request marker:"
  Write-Host "  bundle: $BundleName"
  Write-Host "  to:     $DeviceFilesRoot/workflows/.clear-workflows-request.json"
  Invoke-HdcChecked -Arguments @("file", "send", "-b", $BundleName, $localWorkflows, $DeviceFilesRoot) -FailureMessage "hdc file send clear marker failed"

  if (-not $NoRestartApp) {
    Write-Host "Restarting app so it applies the clear marker..."
    & $Hdc shell "aa force-stop $BundleName" 2>&1 | ForEach-Object { Write-Host $_ }
    & $Hdc shell "aa start -a EntryAbility -b $BundleName -m $ModuleName" 2>&1 | ForEach-Object { Write-Host $_ }
  }

  Write-Host "Done. The App clears workflows on next startup or before the next sync."
  Write-Host "Watch hilog for: DataManagerFacade clear request applied"
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
