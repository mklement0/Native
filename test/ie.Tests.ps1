Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

# For older WinPS versions: set OS/edition flags (which in PSCore are automatically defined).
if (-not (Test-Path Variable:IsWindows)) { $IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $IsCoreCLR = $false }

# Force-(re)import this module.
Remove-Module -ea Ignore -Force (Split-Path -Leaf $PSScriptRoot)
Import-Module $PSScriptRoot/..

Describe 'ie tests' {

  It 'Invokes external executables only.' {
    { ie whoami } | Should -Not -Throw #  -ErrorId InvalidCommandType
    { ie Get-Date } | Should -Throw -ErrorId InvalidCommandType
    { ie select } | Should -Throw -ErrorId InvalidCommandType
    { ie help } | Should -Throw -ErrorId InvalidCommandType
  }

  It 'Properly passes arguments to external executables' {
    # Note: Avoid arguments with embedded newlines, because dbea -Raw
    #       doesn't support them due to line-by-line output.
    $exeArgs = '', 'a&b', '3" of snow', 'Nat "King" Cole', 'c:\temp 1\', 'a \" b'
    $result = dbea -Raw -UseIe $exeArgs
    Compare-Object $exeArgs $result | ForEach-Object { '{0} <{1}>' -f $_.SideIndicator, $_.InputObject } | Should -BeNull
  }

}