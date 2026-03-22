# install-hooks.ps1
# Copies the pre-commit hook into .git/hooks/ and sets it executable.
# Re-run this after cloning or if the hook ever needs to be reinstalled.

$repoRoot = $PSScriptRoot
$source   = Join-Path $PSScriptRoot "pre-commit"
$dest     = Join-Path $repoRoot ".git\hooks\pre-commit"

Copy-Item -Path $source -Destination $dest -Force

# Mark as executable so Git (via Git Bash) will invoke it
$gitExe = (Get-Command git -ErrorAction SilentlyContinue)?.Source
if ($gitExe) {
    & git update-index --chmod=+x pre-commit 2>$null
    # Use git's bundled chmod via sh
    $shExe = Join-Path (Split-Path $gitExe) "sh.exe"
    if (Test-Path $shExe) {
        & $shExe -c "chmod +x '$($dest -replace '\\','/')'"
    }
}

Write-Host "Pre-commit hook installed to .git/hooks/pre-commit" -ForegroundColor Green
