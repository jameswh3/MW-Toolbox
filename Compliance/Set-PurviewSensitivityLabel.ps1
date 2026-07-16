function Set-PurviewSensitivityLabel {
    <#
    .SYNOPSIS
        Applies a Microsoft Purview sensitivity label to all files in a folder.

    .DESCRIPTION
        Recursively processes files in a target folder and applies the specified sensitivity label
        using Set-FileLabel from the PurviewInformationProtection module.

        When running in PowerShell 7, the script automatically delegates all Purview operations
        to Windows PowerShell 5.1 (powershell.exe) where the module loads natively with no
        implicit remoting. Parameters are passed via a temp JSON file to avoid path quoting issues.

        Accepts a sensitivity label GUID (-LabelId).

        Requires the Microsoft Purview Information Protection client installed on the machine.

    .PARAMETER FolderPath
        Root folder containing files to label.

    .PARAMETER LabelId
        Sensitivity label GUID to apply.

    .PARAMETER JustificationMessage
        Optional justification for scenarios where Purview policy requires justification
        (for example, label downgrade).

    .PARAMETER SkipAlreadyLabeled
        If set, files that already have the target label are skipped.

    .PARAMETER NoRecurse
        If set, only files directly inside FolderPath are processed.

    .PARAMETER PassThru
        If set, returns per-file result objects (PS7 mode only; WinPS5.1 mode prints to host).

    .EXAMPLE
        # Apply by GUID directly:
        Set-PurviewSensitivityLabel -FolderPath "C:\Data" `
            -LabelId "11111111-2222-3333-4444-555555555555"

    .EXAMPLE
        Set-PurviewSensitivityLabel -FolderPath "C:\Data" `
            -LabelId "11111111-2222-3333-4444-555555555555" `
            -SkipAlreadyLabeled `
            -JustificationMessage "Standardized by security operations"
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderPath,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$|^$')]
        [string]$LabelId,

        [Parameter(Mandatory = $false)]
        [string]$JustificationMessage,

        [Parameter(Mandatory = $false)]
        [switch]$SkipAlreadyLabeled,

        [Parameter(Mandatory = $false)]
        [switch]$NoRecurse,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru,

    )

    # ----------------------------------------------------------
    # PowerShell 7 path: delegate entirely to WinPS5.1 (no remoting)
    # ----------------------------------------------------------
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "Delegating to Windows PowerShell 5.1 for native Purview compatibility..." -ForegroundColor Yellow

        # Pass parameters via temp JSON to safely handle any path characters
        $tempJson = [System.IO.Path]::GetTempFileName()
        [PSCustomObject]@{
            FolderPath           = $FolderPath
            LabelId              = $LabelId
            SkipAlreadyLabeled   = [bool]$SkipAlreadyLabeled
            NoRecurse            = [bool]$NoRecurse
            JustificationMessage = $JustificationMessage
        } | ConvertTo-Json | Set-Content -Path $tempJson -Encoding UTF8

        $innerScript = @"
`$p = Get-Content -Path '$tempJson' -Raw -Encoding UTF8 | ConvertFrom-Json
Remove-Item '$tempJson' -ErrorAction SilentlyContinue

`$pipPath = 'C:\Program Files (x86)\Microsoft Purview Information Protection\Powershell\PurviewInformationProtection.dll'
try   { Import-Module PurviewInformationProtection -ErrorAction Stop }
catch { Import-Module `$pipPath -ErrorAction Stop }

Write-Host 'Reading label status...' -ForegroundColor Cyan
`$allStatuses = @(Get-FileStatus -Path `$p.FolderPath -ErrorAction SilentlyContinue)
if (`$p.NoRecurse) {
    `$base = (Resolve-Path `$p.FolderPath).Path
    `$allStatuses = @(`$allStatuses | Where-Object { [IO.Path]::GetDirectoryName(`$_.FileName) -eq `$base })
}
Write-Host "Found `$(`$allStatuses.Count) file(s)."

`$labelId = `$p.LabelId

if (-not `$labelId) {
    Write-Host 'ERROR: -LabelId must be provided.' -ForegroundColor Red
    exit 1
}

`$just    = `$p.JustificationMessage
`$updated = 0
`$failed  = 0

Write-Host "Applying label `$labelId to `$(`$allStatuses.Count) file(s)..." -ForegroundColor Cyan

foreach (`$status in `$allStatuses) {
    if (`$p.SkipAlreadyLabeled -and `$status.MainLabelId -eq `$labelId) {
        Write-Host "  SKIP: `$(`$status.FileName)"
        continue
    }
    try {
        `$sp = @{ Path = `$status.FileName; LabelId = `$labelId; ErrorAction = 'Stop' }
        if (`$status.IsLabeled -and -not `$just) {
            `$just = Read-Host 'Enter justification for label change'
        }
        if (`$just) { `$sp.JustificationMessage = `$just }
        `$null = Set-FileLabel @sp
        Write-Host "  OK: `$(`$status.FileName)"
        `$updated++
    } catch {
        Write-Warning "FAIL: `$(`$status.FileName) - `$_"
        `$failed++
    }
}

Write-Host ''
Write-Host 'Summary:' -ForegroundColor Cyan
Write-Host "  Updated: `$updated" -ForegroundColor Green
Write-Host "  Failed:  `$failed"
"@

        $bytes   = [System.Text.Encoding]::Unicode.GetBytes($innerScript)
        $encoded = [Convert]::ToBase64String($bytes)
        & powershell.exe -NoProfile -EncodedCommand $encoded
        return
    }

    # ----------------------------------------------------------
    # Windows PowerShell 5.1 native path (no remoting)
    # ----------------------------------------------------------
    $pipPath = 'C:\Program Files (x86)\Microsoft Purview Information Protection\Powershell\PurviewInformationProtection.dll'
    if (-not (Get-Module -Name PurviewInformationProtection)) {
        try   { Import-Module -Name PurviewInformationProtection -ErrorAction Stop }
        catch {
            if (Test-Path $pipPath) { Import-Module -Name $pipPath -ErrorAction Stop }
            else { throw "PurviewInformationProtection module not found. Expected: $pipPath" }
        }
    }

    if (-not (Test-Path -Path $FolderPath -PathType Container)) {
        throw "FolderPath does not exist or is not a folder: $FolderPath"
    }

    Write-Host "Reading label status..." -ForegroundColor Cyan
    $allStatuses = @(Get-FileStatus -Path $FolderPath -ErrorAction SilentlyContinue)

    if ($NoRecurse) {
        $base = (Resolve-Path $FolderPath).Path
        $allStatuses = @($allStatuses | Where-Object { [IO.Path]::GetDirectoryName($_.FileName) -eq $base })
    }

    Write-Host "Found $($allStatuses.Count) file(s)."

    if (-not $LabelId) {
        throw "-LabelId must be provided."
    }

    $effectiveJust = $JustificationMessage
    $results = [System.Collections.Generic.List[object]]::new()
    $updated = 0
    $failed  = 0

    foreach ($status in $allStatuses) {
        if ($SkipAlreadyLabeled -and $status.MainLabelId -eq $LabelId) {
            $results.Add([pscustomobject]@{ Path = $status.FileName; Status = 'Skipped'; Message = 'Already labeled.' })
            continue
        }

        if ($PSCmdlet.ShouldProcess($status.FileName, "Set-FileLabel -> $LabelId")) {
            try {
                $sp = @{ Path = $status.FileName; LabelId = $LabelId; ErrorAction = 'Stop' }
                if ($status.IsLabeled -and -not $effectiveJust) {
                    $effectiveJust = Read-Host "Enter justification for label change"
                }
                if ($effectiveJust) { $sp.JustificationMessage = $effectiveJust }
                $null = Set-FileLabel @sp
                $results.Add([pscustomobject]@{ Path = $status.FileName; Status = 'Updated'; Message = 'Done.' })
                $updated++
            }
            catch {
                $results.Add([pscustomobject]@{ Path = $status.FileName; Status = 'Failed'; Message = $_.Exception.Message })
                $failed++
            }
        }
    }

    $skipped = ($results | Where-Object Status -eq 'Skipped').Count
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Updated: $updated" -ForegroundColor Green
    Write-Host "  Skipped: $skipped" -ForegroundColor Yellow
    Write-Host "  Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })

    if ($PassThru) { return $results }
}
