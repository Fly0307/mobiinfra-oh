[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateRange(1, [int]::MaxValue)]
  [int]$PrNumber,

  [Parameter(Position = 1)]
  [string]$SafeBranch = "feh_dev",

  [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$GitSafeDirectory = $RepoRoot.Replace("\", "/")

function Invoke-GitChecked {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & git -c "safe.directory=$script:GitSafeDirectory" @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Test-GitRef {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Ref
  )

  & git -c "safe.directory=$script:GitSafeDirectory" show-ref --verify --quiet $Ref
  return $LASTEXITCODE -eq 0
}

Set-Location -LiteralPath $RepoRoot

$isGitRepo = (& git -c "safe.directory=$GitSafeDirectory" rev-parse --is-inside-work-tree 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $isGitRepo -ne "true") {
  throw "This script must be run inside a git repository."
}

$targetBranch = "pr-$PrNumber-merge-test"
$targetRef = "refs/heads/$targetBranch"
$remoteMergeRef = "pull/$PrNumber/merge:$targetBranch"
$currentBranch = (& git -c "safe.directory=$GitSafeDirectory" branch --show-current).Trim()
$targetExists = Test-GitRef $targetRef

Write-Host "PR number: $PrNumber"
Write-Host "Local branch: $targetBranch"
Write-Host "Remote ref: $Remote/$remoteMergeRef"

if ($targetExists -and $currentBranch -eq $targetBranch) {
  if ([string]::IsNullOrWhiteSpace($SafeBranch)) {
    throw "Current branch is $targetBranch. Provide a safe branch to checkout before deleting it."
  }

  Write-Host "Current branch is $targetBranch; checking out $SafeBranch first..."
  Invoke-GitChecked -Arguments @("checkout", $SafeBranch)
}

if ($targetExists) {
  Write-Host "Deleting existing local branch $targetBranch..."
  Invoke-GitChecked -Arguments @("branch", "-D", $targetBranch)
}

Write-Host "Fetching latest PR merge ref..."
Invoke-GitChecked -Arguments @("fetch", $Remote, $remoteMergeRef)

Write-Host "Checking out $targetBranch..."
Invoke-GitChecked -Arguments @("checkout", $targetBranch)

Write-Host "Done. Now on $targetBranch."
