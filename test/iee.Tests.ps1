Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

# For older WinPS versions: Set OS/edition flags (which in PSCore are automatically defined).
# !! At least with Pester v5.x, script-level variables must explicitly created with scope $script:
# !! Do NOT *refer to* these variables with $script: below, however.
if (-not (Test-Path Variable:IsWindows)) { $script:IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $script:IsCoreCLR = $false }

# Force-(re)import this module.
# Target the *.psd1 file explicitly, so the tests can run from versioned subfolders too. Note that the
# loaded module's ModuleInfo's .Path property will reflect the *.psm1 instead.
$manifest = (Get-Item $PSScriptRoot/../*.psd1)
Remove-Module -ea Ignore -Force $manifest.BaseName # Note: To be safe, we unload any modules with the same name first (they could be in a different location and end up side by side in memory with this one.)
Import-Module $manifest -Force -Global # -Global makes sure that when psake runs tester in a child scope, the module is still imported globally.

Describe 'iee tests' {

  It 'Properly invokes a non-failing external command' {
    $expected = whoami
    iee whoami | Should -BeExactly $expected
  }

  It 'Throws with a failing external command' {
    { 
      # !! We mustn't use 2>$null here, as that will unexpectedly create
      # !! entries in the error stream that interfere with the test.
      # !! See https://github.com/PowerShell/PowerShell/issues/3996#issuecomment-666495478
      # !! Unfortunately, that means that whoami's stderr output prints among
      # !! the test results.
      Write-Host -ForegroundColor Green 'Note: The following 2 lines are expected.'
      iee whoami -nosuchoptions 
    } | Should -Throw -ErrorId NativeCommandFailed
  }

}