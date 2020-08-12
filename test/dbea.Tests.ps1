Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

# For older WinPS versions: Set OS/edition flags (which in PSCore are automatically defined).
# !! At least with Pester v5.x, script-level variables must explicitly created with scope $script:
if (-not (Test-Path Variable:IsWindows)) { $script:IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $script:IsCoreCLR = $false }

# Force-(re)import this module.
Remove-Module -ea Ignore -Force (Split-Path -Leaf $PSScriptRoot)
# Target the *.psd1 file explicitly, so the tests can run from versioned subfolders too. Note that the ModuleInfo's .Path property will reflect the *.psm1 instead.
Import-Module (Get-Item $PSScriptRoot/../*.psd1)

Describe 'dbea (Debug-ExecutableArguments) tests' {

  It 'Rejects incompatible switches' {
    { dbea -UseBatchFile -UseWrapperBatchFile } | Should -Throw -ExceptionType System.Management.Automation.ParameterBindingException
  }

  It 'Echoes the arguments in diagnostic form.' {
    
    $argList = 'one', 'two'
    $patternsToFind = $patternsToFindBatchFile = '\b2\b', '\bone\b', '\btwo\b'
    if ($IsWindows) { $patternsToFind += '\bone two\b' } # Windows only, via binary: the whole command-line

    $result = dbea $argList
    ($result | Select-String $patternsToFind).Count | Should -Be $patternsToFind.Count
    # Compare-Object $argList $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull

    if ($IsWindows) {
      $result = dbea -UseWrapperBatchFile $argList
      ($result | Select-String $patternsToFind).Count | Should -Be $patternsToFind.Count

      $result = dbea -UseBatchFile $argList
      ($result | Select-String $patternsToFindBatchFile).Count | Should -Be $patternsToFindBatchFile.Count
    }

  }

  It 'Echoes the arguments as-is with -Raw' {
    $argList = 'one', 'two (2)', 'three'
    # To avoid breaking with arguments that contain cmd.exe metacharacters, the batch file must
    # echo arguments that were passed quoted *with* the quotes.
    $expectedBatchFileResult = 'one', '"two (2)"', 'three'
    $sbFormatUnexpectedOutput = { '{0} <{1}>' -f $_.SideIndicator, $_.InputObject }

    $result = dbea -Raw $argList
    Compare-Object $argList $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull

    if ($IsWindows) {
      $result = dbea -Raw -UseWrapperBatchFile $argList
      Compare-Object $argList $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull

      $result = dbea -Raw -UseBatchFile $argList
      Compare-Object $expectedBatchFileResult $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull
    }

  }

  It 'Passes arguments properly with -UseIe' {
    $argList = 'one', '{ "foo": "bar" }'
    # To avoid breaking with arguments that contain cmd.exe metacharacters, the batch file must
    # echo arguments that were passed quoted *with* the quotes.
    $expectedBatchFileResult = 'one', '"{ ""foo"": ""bar"" }"'
    $sbFormatUnexpectedOutput = { '{0} <{1}>' -f $_.SideIndicator, $_.InputObject }

    $result = dbea -UseIe -Raw $argList
    Compare-Object $argList $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull

    if ($IsWindows) {      
      $result = dbea -UseIe -Raw -UseWrapperBatchFile $argList
      Compare-Object $argList $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull

      $result = dbea -UseIe -Raw -UseBatchFile $argList
      Compare-Object $expectedBatchFileResult $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull
    }
  }

}