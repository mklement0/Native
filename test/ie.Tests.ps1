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

  Context "PlatformNeutral" {

    It 'Only permits calls to external executables' {

      { ie whoami } | Should -Not -Throw
      
      # No other command forms should be accepted: no aliases, functions, cmdlets.
      { ie select } | Should -Throw -ErrorId ApplicationNotFoundException
      { ie cd.. } | Should -Throw -ErrorId ApplicationNotFoundException
      { ie Get-Date } | Should -Throw -ErrorId ApplicationNotFoundException

    }
  
    It 'Properly passes arguments to external executables' {
  
      # Note: Avoid arguments with embedded newlines, because dbea -Raw
      #       doesn't support them due to line-by-line output.
      $exeArgs = '', 'a&b', '3 " of snow', 'Nat "King" Cole', 'c:\temp 1\', 'a b\\', 'a \" b', 'a \"b c\" d', 'a"b', 'ab\'
  
      $result = dbea -Raw -UseIe -- $exeArgs
  
      Compare-Object $exeArgs $result | ForEach-Object { '{0} <{1}>' -f $_.SideIndicator, $_.InputObject } | Should -BeNull
    }  
  
    It 'Properly passes scripts with complex quoting to various interpreters (if installed)' {
      $ohtCmds = [ordered] @{
        # CLIs that require \" and are escaped that way in both editions.
        ruby       = { ie ruby -e 'puts "hi there"' }
        perl       = { ie perl -E 'say "hi there"' }
        pwsh       = { ie pwsh -noprofile -c '"hi there"' }
        powershell = { ie powershell -noprofile -c '"hi there"' }
  
        # CLIs that also accept "" and are used with that escaping in *WinPS*
        node       = { ie node -pe '"hi there"' }
        python     = { ie python -c 'print("hi there")' }
      }
  
      foreach ($exe in $ohtCmds.Keys) {
        if (Get-Command -ea Ignore -Type Application $exe) {
          "Testing with $exe...." | Write-Verbose -vb
          & $ohtCmds[$exe] | Should -BeExactly 'hi there'
        }
      } 
  
    }
  }

  Context "Windows" -Skip:(-not $IsWindows) {

    It 'Handles batch-file quoting needs with space-less arguments' {
  
      # cmd.exe metachars. (in addition to ") that must trigger "..." enclosure:
      #   & | < > ^ , ;
      $exeArgs =
      'a"b', 'a&b', 'a|b', 'a<b', 'a>b', 'a^b', 'a,b', 'a;b', 'last'

      # Note: Batch file always echo arguments exactly as quoted.
      $expected =
      '"a""b"', '"a&b"', '"a|b"', '"a<b"', '"a>b"', '"a^b"', '"a,b"', '"a;b"', 'last' 
  
      -split (dbea -UseIe -UseBatchFile -Raw -- $exeArgs) | Should -BeExactly $expected
  
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
      } else {
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

  }

}
