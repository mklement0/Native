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

Describe 'dbea (Debug-ExecutableArguments) tests' {

  BeforeAll {

    if ($IsWindows) {
      # Delete an existing cached helper *.exe to force its recreation, so the
      # creation on demand can be tested too.
      # (On Unix, we just use an ad-hoc script, not a cached external utility).
      # NOTE: The GUID is a static copy of this module's GUID from the *.psd1 file.
      if ($helperExe = Get-Item -ErrorAction Ignore "$env:TEMP\$($manifest.GUID)\dbea.exe") {
        Remove-Item -LiteralPath $helperExe
      }
    }

    # Helper function for more helpfully showing failed test results, using
    # line-by-line juxtaposition.
    function assert-ExpectedResult ([string[]] $expected, [string[]] $actual) {
      if ($diff = Compare-Object $expected $actual) {
        # Produce line-by-line juxtaposition via Write-Host, to help with troubleshooting:
        $maxNdx = [Math]::Max($expected.Count, $actual.Count) - 1
        $(foreach ($ndx in 0..$maxNdx) {
          '«{0}» vs. «{1}»' -f $expected[$ndx], $actual[$ndx]
        }) | Write-Host -ForegroundColor Yellow
        $diff.Count | Should -Be 0
      }   
    }

  }

  It 'Rejects incompatible switches' {
    { dbea -UseBatchFile -UseWrapperBatchFile } | Should -Throw -ExceptionType System.Management.Automation.ParameterBindingException
  }

  It 'Echoes the arguments in diagnostic form.' {
    
    $argList = 'one', 'two'
    $patternsToFind = $patternsToFindBatchFile = '\b2\b', '\bone\b', '\btwo\b'
    if ($IsWindows) { $patternsToFind += '\bone two\b' } # Windows only, via binary: the whole command-line

    $result = dbea -- $argList
    ($result | Select-String $patternsToFind).Count | Should -Be $patternsToFind.Count
    # Compare-Object $argList $result | ForEach-Object $sbFormatUnexpectedOutput | Should -BeNull

    if ($IsWindows) {
      $result = dbea -UseWrapperBatchFile -- $argList
      ($result | Select-String $patternsToFind).Count | Should -Be $patternsToFind.Count

      $result = dbea -UseBatchFile -- $argList
      ($result | Select-String $patternsToFindBatchFile).Count | Should -Be $patternsToFindBatchFile.Count
    }

  }

  It 'Echoes the arguments as-is with -Raw' {

    $argList = '-u', 'two (2)', 'three'

    $result = dbea -Raw -- $argList
    assert-ExpectedResult $argList $result

  }

  It 'Echoes the arguments as-is with -Raw and -UseBatchFile' -Skip:(-not $IsWindows) {

    $argList = '-u', 'two (2)', 'three'
    # To avoid breaking with arguments that contain cmd.exe metacharacters, the batch file must
    # echo arguments that were passed quoted *with* the quotes.
    $expectedBatchFileResult = '-u', '"two (2)"', 'three'

    $result = dbea -Raw -UseBatchFile -- $argList
    assert-ExpectedResult $expectedBatchFileResult $result

  }

  It 'Echoes the arguments as-is with -Raw and -UseWrapperBatchFile' -Skip:(-not $IsWindows) {

    $argList = '-u', 'two (2)', 'three'

    $result = dbea -Raw -UseWrapperBatchFile -- $argList
    assert-ExpectedResult $argList $result

  }

  It 'Passes arguments properly with -UseIe' {

    # Note: We use an option-like 1st argument to also test the case where 
    #       something that looks like an option isn't mistakenly interpreted
    #       as such by /bin/sh on Unix.
    $argList = '-u', '{ "foo": "bar" }'

    $result = dbea -UseIe -Raw -- $argList
    assert-ExpectedResult $argList $result
  
  }

  It 'Passes arguments properly with -UseIe and -UseBatchFile' -Skip:(-not $IsWindows) {

    $argList = '-u', '{ "foo": "bar" }'
    # To avoid breaking with arguments that contain cmd.exe metacharacters, the batch file must
    # echo arguments that were passed quoted *with* the quotes.
    $expectedBatchFileResult = '-u', '"{ ""foo"": ""bar"" }"'

    $result = dbea -UseIe -Raw -UseBatchFile -- $argList
    assert-ExpectedResult $expectedBatchFileResult $result

  }

  It 'Passes arguments properly with -UseIe and -UseWrapperBatchFile' -Skip:(-not $IsWindows) {

    $argList = '-u', '{ "foo": "bar" }'

    $result = dbea -UseIe -Raw -UseWrapperBatchFile -- $argList
    assert-ExpectedResult $argList $result

  }

}