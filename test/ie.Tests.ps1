Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

# For older WinPS versions: Set OS/edition flags (which in PSCore are automatically defined).
# !! At least with Pester v5.x, script-level variables must explicitly created with scope $script:
if (-not (Test-Path Variable:IsWindows)) { $script:IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $script:IsCoreCLR = $false }

# Force-(re)import this module.
# Target the *.psd1 file explicitly, so the tests can run from versioned subfolders too. Note that the
# loaded module's ModuleInfo's .Path property will reflect the *.psm1 instead.
$manifest = (Get-Item $PSScriptRoot/../*.psd1)
Remove-Module -ea Ignore -Force $manifest.BaseName # Note: To be safe, we unload any modules with the same name first (they could be in a different location and end up side by side in memory with this one.)
Import-Module $manifest

Describe 'ie tests' {

  It 'Only permits calls to external executables' {
    { ie whoami } | Should -Not -Throw
    { ie Get-Date } | Should -Throw -ErrorId InvalidCommandType
    { ie select } | Should -Throw -ErrorId InvalidCommandType
    { ie help } | Should -Throw -ErrorId InvalidCommandType
  }

  It 'Properly passes arguments to external executables' {

    # Note: Avoid arguments with embedded newlines, because dbea -Raw
    #       doesn't support them due to line-by-line output.
    # !! In WinPS, the one edge case `ie` cannot handle is '3" of snow', which WinPS passes as `3" of snow` - without 
    # !! enclosing double quotes, due to the embedded (non-initial) " coming before a space (fortunately fixed in PS Core). 
    # !! Due to `ie`'s escaping that turns into `3\" of snow`
    # !! in the behind-the-scenes command line, which ends up passing *3* arguments - there is no way to workarond that.
    # !! To make the test succeed, we use '3 " of snow' (space before ") in WinPS, in which case the engine does
    # !! double-quote the argument as a whole.
    $exeArgs = '', 'a&b', ('3 " of snow', '3" of snow')[$IsCoreCLR], 'Nat "King" Cole', 'c:\temp 1\', 'a \" b', 'a"b'

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
