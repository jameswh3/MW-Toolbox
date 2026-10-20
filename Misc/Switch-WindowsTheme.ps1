<#
.SYNOPSIS
    Toggles the current user's Windows and app themes between dark and light.

.DESCRIPTION
    Updates the Windows 11 personalization settings for the current user and
    notifies running applications of the change. No administrator rights are
    required. Apps with their own theme settings may not follow Windows.
    Toggle uses the current app theme; an unset app preference defaults to light.

.PARAMETER Mode
    Toggle (default), Light, or Dark. Both Windows and apps use the selected mode.

.EXAMPLE
    .\Misc\Switch-WindowsTheme.ps1

.EXAMPLE
    .\Misc\Switch-WindowsTheme.ps1 -Mode Dark

.EXAMPLE
    .\Misc\Switch-WindowsTheme.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [ValidateSet('Toggle', 'Light', 'Dark')]
    [string]$Mode = 'Toggle'
)

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Switch-WindowsTheme requires Windows.'
}

$personalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$targetMode = $Mode
if ($Mode -eq 'Toggle') {
    $appsUseLightTheme = 1
    if (Test-Path -LiteralPath $personalizePath -ErrorAction Stop) {
        $preferences = Get-ItemProperty -LiteralPath $personalizePath -ErrorAction Stop
        $appPreference = $preferences.PSObject.Properties['AppsUseLightTheme']
        if ($null -ne $appPreference) {
            $appsUseLightTheme = $appPreference.Value
        }
    }
    $targetMode = if ($appsUseLightTheme -eq 0) { 'Light' } else { 'Dark' }
}

if ($PSCmdlet.ShouldProcess('Current user Windows and app themes', "Set $targetMode mode")) {
    $nativeMethods = 'MWToolbox.WindowsTheme.NativeMethods' -as [type]
    if (-not $nativeMethods) {
        $nativeMethods = Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace MWToolbox.WindowsTheme
{
    public static class NativeMethods
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
            uint flags, uint timeout, out UIntPtr result);
    }
}
'@ -PassThru -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $personalizePath -ErrorAction Stop)) {
        $null = New-Item -Path $personalizePath -Force -ErrorAction Stop
    }
    $useLightTheme = if ($targetMode -eq 'Light') { 1 } else { 0 }
    foreach ($property in 'AppsUseLightTheme', 'SystemUsesLightTheme') {
        $null = New-ItemProperty -LiteralPath $personalizePath -Name $property `
            -Value $useLightTheme -PropertyType DWord -Force -ErrorAction Stop
    }

    # Broadcast WM_SETTINGCHANGE without hanging on unresponsive applications.
    $messageResult = [UIntPtr]::Zero
    $notificationResult = $nativeMethods::SendMessageTimeout(
        [IntPtr]0xffff, 0x001a, [UIntPtr]::Zero, 'ImmersiveColorSet',
        0x0002, 2000, [ref]$messageResult)
    if ($notificationResult -eq [IntPtr]::Zero) {
        Write-Warning 'Theme preferences were saved, but the change notification failed or timed out. Some apps may need to be reopened.'
    }

    Write-Host "Windows and app theme preferences set to $targetMode mode." -ForegroundColor Green
}
