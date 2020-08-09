Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

# For older WinPS versions: set OS/edition flags (which in PSCore are automatically defined).
if (-not (Test-Path Variable:IsWindows)) { $IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $IsCoreCLR = $false }

# Force-(re)import this module.
Remove-Module -ea Ignore -Force (Split-Path -Leaf $PSScriptRoot)
Import-Module $PSScriptRoot/..

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