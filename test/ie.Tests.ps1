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
        $diff.Count | Should -Be 0
      }   
    }
    
  }

  Context "PlatformNeutral" {

    It 'Passes script-block-based PowerShell calls through as-is' {
      ('pwsh', ('pwsh.exe', 'powershell.exe'))[$IsWindows].ForEach({
        ie pwsh -noprofile -c { "[$args]" } -args one, two | Should -Be '[one two]'
      })
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
      $exeArgs = '', 'a&b', '3 " of snow', 'Nat "King" Cole', 'c:\temp 1\', 'a b\\', 'a \" b', 'a \"b c\" d', 'a"b', 'ab\'
  
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
          "Testing with $exe...." | Write-Verbose -vb
          $expected = if ($exe -eq 'Rscript') { '[1] "hi there"' } else { 'hi there' }
          & $ohtCmds[$exe] | Should -BeExactly $expected
        }
      } 
  
    }
  }

  Context "Windows" -Skip:(-not $IsWindows) {

    It 'Handles batch-file quoting needs with space-less arguments' {
  
      # cmd.exe metachars. (in addition to ") that must trigger "..." enclosure:
      #   & | < > ^ , ;
      # Note: `=` too requires "..." enclosure in batch-file argument parsing, but it conflicts
      #       with keeping the LHS of tokens such as `FOO=bar` *unquoted* to support misexec-style CLIs,
      #       and we give precedence to the latter rule.
      $exeArgs =
      'a"b', 'a&b', 'a|b', 'a<b', 'a>b', 'a^b', 'a,b', 'a;b', 'a=b', 'the last one'

      # Note: Batch files always echo arguments exactly as quoted.
      #       Note the - unavoidable - spltting of 'a=b' into 'a' and 'b'
      $expected =
      '"a""b"', '"a&b"', '"a|b"', '"a<b"', '"a>b"', '"a^b"', '"a,b"', '"a;b"', 'a', 'b', '"the last one"' 
  
      $actual = (dbea -UseIe -UseBatchFile -Raw -- $exeArgs) -split '\r\n'
      assert-ExpectedResult $expected $actual        
  
    }

    It 'Handles partial-quoting needs of CLIs such as msiexec.exe' {
  
      # Arguments of the following form must be placed with *partial double-quoting*,
      # *around the value only* on the command line (e.g., `foo="bar none"`):
      $argsToPartiallyQuote = if ($PSVersionTable.PSVersion.Major -le 4) {
        # !! CAVEAT: In WinPS v3 and v4 only, *a partially quoted value that contains spaces*, such as `foo="bar none"`,
        # !! causes the engine to still enclose the entire argument in "...", which cannot be helped.
        # !! Only a space-less value that needs quoting is handled correctly (which may never occur in practice).
        Write-Warning "Partial quoting of msiexec-style arguments with spaces not supported in v3 and v4, skipping test."
        'foo=bar"none'
      }
      else {
        # !! In PS Core, verbatim `foo=bar"none` would only become `'foo="bar""none"` if the executable were msiexec.exe, msdeploy.exe, or cmdkey.exe; 
        # !! otherwise - as in these tests - \"-escaping kicks in and `foo=bar"none` becomes `foo=bar\"none` instead - without syntactic double-quoting around the value.
        'foo=bar none', '/foo:bar none', '-foo:bar none', 'foo=bar "stuff" none' + ('foo=bar"none', @())[$IsCoreCLR]
      }
      
      $argsToPartiallyQuote | ForEach-Object {
  
        $exeArgs = $_, 'a " b'  # Add a second argument.

        # The value part be selectively quoted.
        # ""-escaping must also be triggered (it's what msiexec requires).
        # !! In WinPS we use ""-escaping by default anyway, to work around legacy bugs, 
        # !! but in *PS Core* we default to \"-escaping, because it is the safer choice; as a nod to 
        # !! these high-profile CLIs, we have *hard-coded exceptions for 'msiexece' and 'msdeploy' there.
        # !! We therefore can't test this aspect on PS Core. A manual way to do it is to create (temporary)
        # !! copies of de.exe, name them 'msiexec.exe' and 'msdeploy.exe', then call them with `ie`; e.g.:
        # !!
        # !!   'msiexec.exe', 'msdeploy.exe' | % { cpi -ea stop (gcm de.exe).Path "./$_"; ie "./$_" 'foo=bar none', '/foo:bar none', '-foo:bar none', 'foo=bar "stuff" none', 'foo=bar"none'; ri "./$_" }
        # !!  
        $partiallyQuotedArg = (($_ -replace '"', ('""', '\"')[$IsCoreCLR]) -replace '(?<=[:=]).+$', '"$&"')
        $expectedRawCmdLine = '{0} {1}' -f $partiallyQuotedArg, ('"a "" b"', '"a \" b"')[$IsCoreCLR]

        # Run dbea and extract the raw command line from the output (last non-blank line.)
        $rawCmdLine = ((dbea -UseIe -- $exeArgs) -notmatch '^\s*$')[-1].Trim()

        $rawCmdLine | Should -BeExactly $expectedRawCmdLine
  
      }  

      
    }  
    
    It 'Handles a *single-argument* command-line cmd.exe /c call correctly.' {
  
      $expected = 'Ready to move on [Y,N]?Y'
      $choicePath = (Get-Command -ea Stop choice.exe).Source

      # Command line passed as single argument with embedded quoting.
      ie cmd.exe /c (' "{0}" /d Y /t 0 /m "Ready to move on" ' -f $choicePath) | Should -BeExactly $expected
  
    }

    It 'Handles a *multi-argument* command-line cmd.exe /c call correctly.' {
  
      $expected = 'Ready to move on [Y,N]?Y'
      $choicePath = (Get-Command -ea Stop choice.exe).Source

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

      # Similiar command line as above, but passed as multiple arguments,
      # with the executable path containing spaces, if feasible.
      ie cmd.exe /c $choicePath /d Y /t 0 /m "Ready to move on" | Should -BeExactly $expected

      if ($IsCoreCLR)  {
        Remove-Item -LiteralPath $tmpSymlinkWithSpaces
      }
  
    }

    It 'Batch-file calls via "cmd /c call" for robust exit-code reporting work.' {

      # For added testing:
      #  * use a batch-file name with spaces
      #  * pass escape-triggering dummy arguments.
      $tempBatFile = Join-Path (Get-Item TestDrive:/).FullName 'tmp 1.cmd'
      $dummyArgs = 'foo&bar', 'unrelated "stuff"'

      # Create a temporary batch file that uses exit /b *without* an explicit
      # exit code, which should pass the failing command's exit code (error level) through.
      # This only happens when the batch file is called via `cmd /c call`
      '@echo off & whoami -nosuch 2>NUL || exit /b' | Set-Content -LiteralPath $tempBatFile
      
      $output = ie cmd /c call $tempBatFile $dummyArgs 2>&1

      Remove-Item $tempBatFile

      $output | Should -BeNullOrEmpty
      $LASTEXITCODE | Should -Be 1

    }

  }

}
