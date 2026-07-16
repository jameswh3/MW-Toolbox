# install-hooks.ps1
# Copies the pre-commit hook into .git/hooks/ and sets it executable.
# Re-run this after cloning or if the hook ever needs to be reinstalled.

<<<<<<<< HEAD:scripts/git/install-hooks.ps1
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source   = Join-Path $repoRoot "pre-commit"
========
$repoRoot = Split-Path $PSScriptRoot -Parent
$source   = Join-Path $repoRoot ".githooks\pre-commit"
>>>>>>>> 1f8fa8f4ad29e6a5071354bdc86176d820854b7e:scripts/install-hooks.ps1
$dest     = Join-Path $repoRoot ".git\hooks\pre-commit"

Copy-Item -Path $source -Destination $dest -Force

# Mark as executable so Git (via Git Bash) will invoke it
$gitExe = (Get-Command git -ErrorAction SilentlyContinue)?.Source
if ($gitExe) {
    & git update-index --chmod=+x .githooks/pre-commit 2>$null
    # Use git's bundled chmod via sh
    $shExe = Join-Path (Split-Path $gitExe) "sh.exe"
    if (Test-Path $shExe) {
        & $shExe -c "chmod +x '$($dest -replace '\\','/')'"
    }
}

Write-Host "Pre-commit hook installed to .git/hooks/pre-commit" -ForegroundColor Green
