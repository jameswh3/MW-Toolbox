$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$themeScript = Join-Path $repositoryRoot 'Misc\Switch-WindowsTheme.ps1'
$menuScript = Join-Path $repositoryRoot 'Menu.ps1'

# Stub the native API in this test process so no real theme notification is sent.
if (-not ('MWToolbox.WindowsTheme.Tests.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
namespace MWToolbox.WindowsTheme.Tests
{
    public static class NativeMethods
    {
        public static int Calls;
        public static bool Fail;
        public static IntPtr SendMessageTimeout(
            IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
            uint flags, uint timeout, out UIntPtr result)
        {
            Calls++;
            result = UIntPtr.Zero;
            return Fail ? IntPtr.Zero : new IntPtr(1);
        }
    }
}
'@
}

Describe 'Windows theme toggle' {
    BeforeEach {
        $global:MWToolboxThemeTestState = @{
            Preferences = [pscustomobject]@{ AppsUseLightTheme = 1; SystemUsesLightTheme = 1 }
            KeyExists = $true
            Writes = @{}
            MenuReads = 0
        }
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Calls = 0
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Fail = $false
        Mock Add-Type { [MWToolbox.WindowsTheme.Tests.NativeMethods] }
        Mock Test-Path { $global:MWToolboxThemeTestState.KeyExists } -ParameterFilter {
            $LiteralPath -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        }
        Mock Get-ItemProperty { $global:MWToolboxThemeTestState.Preferences }
        Mock New-Item {}
        Mock New-ItemProperty {
            $global:MWToolboxThemeTestState.Writes[$Name] = $Value
        }
        Mock Write-Host {}
        Mock Write-Warning {}
    }

    AfterEach {
        Remove-Variable -Name MWToolboxThemeTestState -Scope Global
    }

    It 'sets both DWORD preferences correctly: <Case>' -TestCases @(
        @{ Case = 'light to dark'; Mode = 'Toggle'; Apps = 1; System = 1; Expected = 0 }
        @{ Case = 'dark to light'; Mode = 'Toggle'; Apps = 0; System = 0; Expected = 1 }
        @{ Case = 'mixed to light'; Mode = 'Toggle'; Apps = 0; System = 1; Expected = 1 }
        @{ Case = 'mixed to dark'; Mode = 'Toggle'; Apps = 1; System = 0; Expected = 0 }
        @{ Case = 'explicit light'; Mode = 'Light'; Apps = 1; System = 0; Expected = 1 }
        @{ Case = 'explicit dark'; Mode = 'Dark'; Apps = 0; System = 1; Expected = 0 }
    ) {
        param ($Case, $Mode, $Apps, $System, $Expected)
        $global:MWToolboxThemeTestState.Preferences = [pscustomobject]@{ AppsUseLightTheme = $Apps; SystemUsesLightTheme = $System }
        & $themeScript -Mode $Mode
        $global:MWToolboxThemeTestState.Writes.Count | Should Be 2
        $global:MWToolboxThemeTestState.Writes['AppsUseLightTheme'] | Should Be $Expected
        $global:MWToolboxThemeTestState.Writes['SystemUsesLightTheme'] | Should Be $Expected
        Assert-MockCalled New-ItemProperty -Times 2 -Exactly -Scope It -ParameterFilter {
            $PropertyType -eq 'DWord' -and $Force
        }
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Calls | Should Be 1
    }

    It 'defaults an unset app preference to light' {
        $global:MWToolboxThemeTestState.Preferences = [pscustomobject]@{}
        & $themeScript
        $global:MWToolboxThemeTestState.Writes['AppsUseLightTheme'] | Should Be 0
    }

    It 'creates a missing personalization key' {
        $global:MWToolboxThemeTestState.KeyExists = $false
        & $themeScript
        Assert-MockCalled New-Item -Times 1 -Exactly -Scope It
        $global:MWToolboxThemeTestState.Writes['AppsUseLightTheme'] | Should Be 0
        $global:MWToolboxThemeTestState.Writes['SystemUsesLightTheme'] | Should Be 0
    }

    It 'does not change settings or notify applications with WhatIf' {
        & $themeScript -WhatIf
        Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
        Assert-MockCalled New-ItemProperty -Times 0 -Exactly -Scope It
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Calls | Should Be 0
    }

    It 'rejects unsupported modes without writing settings' {
        $validationError = $null
        try {
            & $themeScript -Mode Invalid -ErrorAction Stop
        }
        catch {
            $validationError = $_
        }
        ($null -ne $validationError) | Should Be $true
        $validationError.Exception.GetType().Name | Should Be 'ParameterBindingValidationException'
        Assert-MockCalled New-ItemProperty -Times 0 -Exactly -Scope It
    }

    It 'surfaces registry write failures without reporting success' {
        Mock New-ItemProperty { throw 'Registry access denied' }
        { & $themeScript } | Should Throw 'Registry access denied'
        Assert-MockCalled Write-Host -Times 0 -Exactly -Scope It
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Calls | Should Be 0
    }

    It 'warns when notification fails after saving settings' {
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Fail = $true
        & $themeScript
        $global:MWToolboxThemeTestState.Writes.Count | Should Be 2
        Assert-MockCalled Write-Warning -Times 1 -Exactly -Scope It
    }

    It 'runs the toggle through the System menu and then exits' {
        Mock Read-Host {
            $global:MWToolboxThemeTestState.MenuReads++
            if ($global:MWToolboxThemeTestState.MenuReads -eq 1) {
                return [string]($menuLookup.GetEnumerator() |
                    Where-Object Value -eq 'Toggle Windows Dark/Light Mode' |
                    Select-Object -ExpandProperty Key)
            }
            return [string]($menuLookup.GetEnumerator() |
                Where-Object Value -eq 'Exit' |
                Select-Object -ExpandProperty Key)
        }
        $originalUpn = $env:UPN
        try {
            $env:UPN = 'theme-test'
            & $menuScript
        }
        finally {
            $env:UPN = $originalUpn
        }
        $global:MWToolboxThemeTestState.MenuReads | Should Be 2
        $global:MWToolboxThemeTestState.Writes['AppsUseLightTheme'] | Should Be 0
        $global:MWToolboxThemeTestState.Writes['SystemUsesLightTheme'] | Should Be 0
        [MWToolbox.WindowsTheme.Tests.NativeMethods]::Calls | Should Be 1
    }
}
