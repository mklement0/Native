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

Describe 'ie tests' {

  BeforeAll {

    # Helper function for more helpfully showing failed test results, using
    # line-by-line juxtaposition.
    function assert-ExpectedResult ([string[]] $expected, [string[]] $actual) {
      if ($diff = Compare-Object $expected $actual) {
        # Produce line-by-line juxtaposition via Write-Host, to help with troubleshooting:
        $maxNdx = [Math]::Max($expected.Count, $actual.Count) - 1
        $(foreach ($ndx in 0..$maxNdx) {
          '«{0}» vs. «{1}»' -f $expected[$ndx], $actual[$ndx]
        }) | Write-Host -ForegroundColor Yellow
        $diff | Should -BeNullOrEmpty
      }   
    }
    
  }

  Context "PlatformNeutral" {

    It 'Passes script-block-based PowerShell calls through as-is' {
      foreach ($cli in ('pwsh', ('pwsh.exe', 'powershell.exe'))[$IsWindows]) {
        if (-not (Get-Command -ErrorAction Ignore -CommandType Application $cli)) { Write-Warning "Ignoring unavailability of '$cli'."; continue } # Ignore nonexistence of pwsh.exe on Windows, for testing on the WinPS v3 and v4 VMs
        ie $cli -noprofile -c { "[$args]" } -args one, two | Should -Be '[one two]'
      }
    }

    It 'Only permits calls to external executables' {

      # Note: `whoami` exists on both Windows and Unix-like platforms.
      { ie whoami } | Should -Not -Throw
      # An *alias* of an external executable is allowed too.
      # Note: `-Scope Global` is required for `ie` to see the alias, due to being defined in a module.
      #       !! For WinPS compatibility, do NOT use Remove-Alias to clean up the alias, use RemoveItem Alias: instead.
      { Set-Alias -Scope Global __exealias_$PID whoami; try { ie __exealias_$PID } finally { Remove-Item "Alias:__exealias_$PID" } } | Should -Not -Throw
      
      # No other command forms should be accepted: aliases of non-executables, functions, cmdlets.
      { ie select } | Should -Throw -ErrorId ApplicationNotFoundException
      { ie cd.. } | Should -Throw -ErrorId ApplicationNotFoundException
      { ie Get-Date } | Should -Throw -ErrorId ApplicationNotFoundException

    }
  
    It 'Properly passes arguments to external executables' {
  
      # Note: Avoid arguments with embedded newlines, because dbea -Raw
      #       doesn't support them due to line-by-line output.
      $exeArgs = '', 'a&b', '3 " of snow', 'Nat "King & I" Cole', 'c:\temp 1\', 'a b\\', 'a \" b', 'a \"b c\" d', 'a"b', 'ab\'
  
      $result = dbea -Raw -UseIe -- $exeArgs
      assert-ExpectedResult $exeArgs $result

    }  
  
    It 'Properly passes scripts with complex quoting to various interpreters (if installed)' {
      $ohtCmds = [ordered] @{
        # CLIs that require \" and must be escaped that way in WinPS too.
        ruby       = { ie ruby -e 'puts "hi there"' }
        perl       = { ie perl -E 'say "hi there"' }
        Rscript    = { ie Rscript -e 'print("hi there")' }
        pwsh       = { ie pwsh -noprofile -c '"hi there"' }
        powershell = { ie powershell -noprofile -c '"hi there"' }
  
        # CLIs that also accept "" and are used with that escaping in *WinPS*
        node       = { ie node -pe '"hi there"' }
        python     = { ie python -c 'print("hi there")' }
      }
  
      foreach ($exe in $ohtCmds.Keys) {
        if (Get-Command -ea Ignore -Type Application $exe) {
          "Testing with installed CLI '$exe'...." | Write-Verbose -vb
          $expected = if ($exe -eq 'Rscript') { '[1] "hi there"' } else { 'hi there' }
          & $ohtCmds[$exe] | Should -BeExactly $expected
        }
      } 
  
    }
  }

  Context "Windows" -Skip:(-not $IsWindows) {

    It 'Uses ""-escaping for batch-file calls' {
      $exeArgs = 'Andre "The Hawk" Dawson', 'another argument'
      $expected = '"Andre ""The Hawk"" Dawson"', '"another argument"' # !! Batch files echo argumens exactle as quoted on the command line.
      assert-ExpectedResult $expected (dbea -UseIe -UseBatchFile -Raw $exeArgs)
    }

    It 'Uses ""-escaping for WSH calls' {
      $exeArgs  = 'Andre "The Hawk" Dawson', 'another argument'
      $expected = 'Andre The Hawk Dawson',   'another argument' # !! WSH doesn't support embedded " chars., but if `ie` "escapes" them as "", as it should, WSH at least maintains argument boundaries, while stripping the ".
      assert-ExpectedResult $expected (dbea -UseIe -UseWSH -Raw $exeArgs)
    }

    It 'Handles partial-quoting needs of CLIs such as msiexec.exe' {
  
      # Arguments of the following form must be placed with *partial double-quoting*,
      # *around the value only* on the command line (e.g., `foo="bar none"`):
      $argsToPartiallyQuote = 'foo=bar none', '/foo:bar none', '-foo:bar none', 'foo=bar "stuff" none','foo=bar"none'

      $argsToPartiallyQuote | ForEach-Object {
  
        # Set the test-override environment variable to force `ie` to use ""-escaping, as
        # if msiexec.exe, msdeploy.exe or cmdkey.exe were being called, the hard-coded
        # msiexec-like executables that 
        $env:__ie_doubledquotes = 1

        $exeArgs = $_, 'a " b'  # Add a second argument, as a control.

        try {
          # The value part must be selectively quoted.
          $partiallyQuotedArg = ($_ -replace '"', '""' -replace '(?<=[:=]).+$', '"$&"') # turn `'foo=bar none` into `foo="bar none"`, ...
          $expectedRawCmdLine = '{0} {1}' -f $partiallyQuotedArg, '"a "" b"'
  
          # Run dbea and extract the raw command line from the output (last non-blank line.)
          $rawCmdLine = ((dbea -UseIe -- $exeArgs) -notmatch '^\s*$')[-1].Trim()
          $rawCmdLine | Should -BeExactly $expectedRawCmdLine
  
          # --- Should also work when a *batch file* is (first) invoked, in which case ""-escaping must be used even in PS Core.
          # See above.
          $partiallyQuotedArg = (($_ -replace '"', '""') -replace '(?<=[:=]).+$', '"$&"')
          $expectedRawCmdLine = '{0} {1}' -f $partiallyQuotedArg, '"a "" b"'
  
          # Run dbea *via a wrapper batch file* and extract the raw command line from the output (last non-blank line.)
          $rawCmdLine = ((dbea -UseWrapperBatchFile -UseIe -- $exeArgs) -notmatch '^\s*$')[-1].Trim()
          $rawCmdLine | Should -BeExactly $expectedRawCmdLine
        }
        finally {
          $env:__ie_doubledquotes = $null
        }
        
      }  

      
    }  
    
    It 'Handles a *single-argument* command-line cmd.exe /c call correctly.' {
  
      $expected = 'Ready to move on [Y,N]?Y'
      $choicePath = (Get-Command -ea Stop choice.exe).Path # !! Use .Path, not .Source - the latter doesn't work in WinPS v3.

      # Command line passed as single argument with embedded quoting.
      ie cmd.exe /c (' "{0}" /d Y /t 0 /m "Ready to move on" ' -f $choicePath) | Should -BeExactly $expected
  
    }

    It 'Handles a *multi-argument* command-line cmd.exe /c call correctly.' {
  
      $expected = 'Ready to move on [Y,N]?Y'
      $choicePath = (Get-Command -ea Stop choice.exe).Path # !! Use .Path, not .Source - the latter doesn't work in WinPS v3.

      # We want to use an executable path *with spaces*, so that PowerShell
      # "..."-encloses it, as that is the real test for whether `ie` correctly
      # merges the multiple arguments into a single one.
      # (Without this merging, cmd.exe would see a double-quoted *first* argument, followed by *another* double-quoted argument, which breaks syntactially.)
      if ($IsCoreCLR)  {
        # Note: This requires the opt-in to NOT require elevation for creating symlinks.
        $tmpSymlinkWithSpaces = (New-Item -ea Stop "temp:/dir with spaces $PID" -Type SymbolicLink -Value (Split-Path $choicePath)).FullName
        $choicePath = Join-Path $tmpSymlinkWithSpaces (Split-Path -Leaf $choicePath)
      }
      else {
        # On WinPS, ELEVATION is required to create symlink, so we use the space-less path as-is.
        # This should be fine, given that the tests *also* run in PS Core, and that the PowerShell
        # part of the invocation should behave the same between editions.
      }

      try {
        # Similiar command line as above, but passed as multiple arguments,
        # with the executable path containing spaces, if feasible.
        ie cmd.exe /c $choicePath /d Y /t 0 /m "Ready to move on" | Should -BeExactly $expected
      }
      finally {
        if ($IsCoreCLR)  {
          Remove-Item -LiteralPath $tmpSymlinkWithSpaces
        }
      }
  
    }

    It 'Passing arguments with cmd.exe metacharacters to batch file works' {

      $tempBatFile = Join-Path (Get-Item TestDrive:/).FullName 'tmp.cmd'
      $exeArgs = 'foo1&bar1', 'foo2|bar2', 'foo3^bar3', 'foo4<bar4', 'foo5>bar5', 'foo6,bar6', 'foo7;bar7', 'foo8=bar8', 'more "stuff"', 'last'
      # Note how all space-less args with metachars. must end up double-quoted, except foo8=bar8, due to the misexec-like exception.
      $expected = '"foo1&bar1" "foo2|bar2" "foo3^bar3" "foo4<bar4" "foo5>bar5" "foo6,bar6" "foo7;bar7" foo8=bar8 "more ""stuff""" last'

      try {

          '@echo %*' | Set-Content -LiteralPath $tempBatFile

          $output = ie $tempBatFile $exeArgs 2>&1           
          $output | Should -Be $expected
          $LASTEXITCODE | Should -Be 0

      }
      finally {
        Remove-Item $tempBatFile
      }

    }


    It 'Invoking batch files with quoted paths works' {

      $tempBatFile = Join-Path (Get-Item TestDrive:/).FullName 'tmp 1.cmd'
      $exeArgs = 'foo1&bar1', 'foo2|bar2', 'foo3^bar3', 'foo4<bar4', 'foo5>bar5', 'foo6,bar6', 'foo7;bar7', 'foo8=bar8', 'more "stuff"', 'last'
      # Note how all space-less args with metachars. must end up double-quoted, except foo8=bar8, due to the misexec-like exception.
      $expected = '"foo1&bar1" "foo2|bar2" "foo3^bar3" "foo4<bar4" "foo5>bar5" "foo6,bar6" "foo7;bar7" foo8=bar8 "more ""stuff""" last'

      try {

          '@echo %*' | Set-Content -LiteralPath $tempBatFile

          $output = ie $tempBatFile $exeArgs 2>&1 
          $output | Should -Be $expected
          $LASTEXITCODE | Should -Be 0

      }
      finally {
        Remove-Item $tempBatFile
      }

    }


    It 'Robust batch-file exit-code reporting works' {

      # For added testing:
      #  * use a batch-file name with spaces
      #  * pass escape-triggering dummy arguments.
      $tempBatFile = Join-Path (Get-Item TestDrive:/).FullName 'tmp 1.cmd'
      $dummyArgs = 'foo&bar', 'unrelated "stuff"'

      try {

          # Create a temporary batch file that uses exit /b *without* an explicit
          # exit code, which should pass the failing command's exit code (error level) through.
          # This only happens when the batch file is called via `cmd /c ... & exit `
          # See https://stackoverflow.com/q/66975883/45375
          '@echo off & whoami -nosuch 2>NUL || exit /b' | Set-Content -LiteralPath $tempBatFile

          $output = ie $tempBatFile $dummyArgs 2>&1  
          $output | Should -BeNullOrEmpty
          $LASTEXITCODE | Should -Be 1

          # As a control: Rewrite the batch file to succeed.
          '@echo off & whoami & exit /b' | Set-Content -LiteralPath $tempBatFile
          $output = ie $tempBatFile $dummyArgs 2>&1  
          $output | Should -Be (whoami)
          $LASTEXITCODE | Should -Be 0

      }
      finally {
        Remove-Item $tempBatFile
      }
      
    }

  }

}
