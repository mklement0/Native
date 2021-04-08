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

Describe 'ins (Invoke-NativeShell) tests' {

  # Note: There's one scenario we cannot test in an automated fashion:
  #       Making sure that if the invoked commands are passed *by argument*
  #       that interactive prompts still work.
  #       To make this work, `$Input | ...` must *not* be used for invocation in that scenario:
  #       Even if there is no actual pipeline input, PowerShell will redirect stdin,
  #       pipe nothing to it, so the prompt will not display and the variable will
  #       receive no value.
  #       Commands for interactive testing: these should prompt for a value and echo it.
  #          Windows:
  #            ins 'setlocal enabledelayedexpansion & set /p var="Enter a value: " & echo !var!'
  #          Unix:
  #            ins 'read -p "Enter a value: " var; printf ''%s\n'' "$var"'

  Context 'PlatformNeutral' {

    It 'Throws an error for a nonzero exit code with -ErrorOnFailure / -e' {      
      $cmd = 'whoami -nosuchoptions'
      # Note: Due to the bug up to 7.0 where stderr output being redirected
      #       causing $ErrorActionPreference to apply , *>$null would trigger
      #       a script-terminating error, given that 'Stop' is in effect.
      #       Invocations via Psake invariably have this effect.
      Write-Host -ForegroundColor Green 'Note: The following 4 lines are expected.'
      { ins -e $cmd } | Should -Throw -ErrorId NativeCommandFailed
      { ins -ErrorOnFailure $cmd } | Should -Throw -ErrorId NativeCommandFailed
    }

    It 'Passing arguments to the -CommandLine string triggers a warning if the arguments aren''t referenced.' {
      
      # Commands that do not include argument (parameter) references.
      $cmdsWarn = 'echo', 'echo 10%', 'echo 5$', 'echo $RANDOM'
      # Commands that do.
      $cmdsDontWarn = if ($IsWindows) {
        'echo %*', 'echo %1', 'echo %~1', 'echo %~dp1'
      } else {
        'echo $*', 'echo ${*}', 'echo $@', 'echo ${@}', 'echo $1', 'echo ${1}'
      }

      $cmdsWarn | ForEach-Object {
        $null = ins -WarningVariable warnings -- $_ foo 3>$null
        if ($warnings.Count -eq 0) { Write-Verbose -vb "Command: $_"}
        $warnings.Count | Should -Be 1
      }

      $cmdsDontWarn | ForEach-Object {
        $null = ins -WarningVariable warnings -- $_ foo
        if ($warnings.Count -ne 0) { Write-Verbose -vb "Command: $_"}
        $warnings.Count | Should -Be 0
      }

    }

  }

  Context 'Windows' -Skip:(-not $IsWindows) {
  
    It 'Reflects the native shell''s exit code in $LASTEXITCODE' {
      $successCommand = 'echo.'
      $failureCommand = 'echo a | findstr b'
      
      & { $null = ins $successCommand; $LASTEXITCODE } | Should -Be 0
      & { $null = ins $failureCommand; $LASTEXITCODE } | Should -Be 1
    }

    It 'Correctly invokes a cmd.exe command line via an argument' {
      ins 'echo "1"&echo 2' | Should -Be '"1"', '2'
    }
  
    It 'Correctly invokes a cmd.exe command line via stdin (pipeline)' {
      'echo "1"&echo 2' | ins | Should -Be '"1"', '2'
    }
  
    It 'Correctly invokes a cmd.exe command line via an argument and wth pass-through arguments' {
      ins 'echo %2' one foo | Should -Be foo
    }

    It 'Correctly invokes a cmd.exe command line via stdin (pipeline) and with pass-through arguments' {
      'echo %2' | ins - one foo | Should -Be foo
    }


    It 'Correctly passes pipeline (stdin) data to a cmd.exe command line' {
      'foo', 'bar' | ins 'findstr "bar" & echo ''hi''' | Should -Be 'bar', "'hi'"
      'foo', 'bar' | ins 'findstr "%1" & echo ''hi''' 'bar' | Should -Be 'bar', "'hi'"
    }

    It 'A multi-line string with line continuations works as expected.' {
      "echo a^`nb^`nc" | ins | Should -Be 'abc'
    }

    It 'A multi-line string with individual commands works as expected.' {
      $cmd = "echo one`necho two"
      $expected = 'one', 'two'
      ins $cmd | Should -Be $expected
      $cmd | ins | Should -Be $expected
    }

    It 'Calling a batch file reliably reports its exit code.' {

      # For added testing:
      #  * use a batch-file name with spaces
      #  * pass escape-triggering dummy arguments.
      $tempBatFile = Join-Path (Get-Item TestDrive:/).FullName 'tmp 1.cmd'
      $inArgsStr = '"foo&bar" "unrelated ""stuff"""'
      $echoedArgsStr = '[{0}] ' -f $inArgsStr # Note the trailing ' ' to account for cmd.exe's `echo` behavior.

      # Create a temporary batch file that uses exit /b *without* an explicit
      # exit code, which should pass the failing command's exit code (error level) through.
      # This only happens when the batch file is called via `cmd /c ... & exit `
      # See https://stackoverflow.com/q/66975883/45375
      '@echo off & echo [%*] & whoami -nosuch 2>NUL || exit /b' | Set-Content -LiteralPath $tempBatFile
      
      $output = ins "`"$tempBatFile`" $inArgsStr"  2>&1

      Remove-Item $tempBatFile

      $output | Should -Be $echoedArgsStr
      $LASTEXITCODE | Should -Be 1

    }


  }

  Context 'Unix' -Skip:$IsWindows {

    It 'Uses /bin/bash by default, /bin/sh if requested' {
    
      # Note: Hypothetically, if the system running these tests doesn't have /bin/bash,
      #       the test fails due to fallback to /bin/sh.

      # Command that echoes the full executable path.
      # Note: `ps -o comm=` outputs just 'bash' on Linux, not '/bin/bash', for instance.
      #       `-o args` is the whole command line, but it is POSIX-mandated, so we can rely on it.
      #       We use awk to extract the first argument, which is the executable path used.
      $cmd = ' ps -p $$ -o args= | awk ''{ print $1 }'' ' 

      ins $cmd | Should -Be '/bin/bash'
      ins -UseSh $cmd | Should -Be '/bin/sh'

    }

    It 'Reflects the native shell''s exit code in $LASTEXITCODE' {
      $successCommand = 'true'
      $failureCommand = 'false'
      
      & { ins $successCommand; $LASTEXITCODE } | Should -Be 0
      & { ins -UseSh $successCommand; $LASTEXITCODE } | Should -Be 0

      & { ins $failureCommand; $LASTEXITCODE } | Should -Be 1
      & { ins -UseSh $failureCommand; $LASTEXITCODE } | Should -Be 1

    }
    
    It 'Correctly invokes a bash/sh command line via an argument' {
      $cmd = 'ls -d ~ | cat -n; echo "hi"'
      $expected = '1', $HOME, 'hi'
      -split (ins $cmd) | Should -Be $expected
      -split (ins -UseSh $cmd) | Should -Be $expected
    }

    It 'Correctly invokes a bash/sh command line via stdin (pipeline)' {
      $cmd = 'ls -d ~ | cat -n; echo "hi"'
      $expected = '1', $HOME, 'hi'
      -split ($cmd | ins) | Should -Be $expected
      -split ($cmd | ins -UseSh) | Should -Be $expected
    }

    It 'Correctly invokes a bash/sh command line via an argument and with pass-through arguments' {
      $cmd = 'ls -d "$1" | cat -n; echo "$2"'
      $cmdArgs = $HOME, 'hi'
      $expected = '1', $HOME, 'hi'
      -split (ins $cmd $cmdArgs) | Should -Be $expected
      -split (ins -UseSh $cmd $cmdArgs) | Should -Be $expected
    }

    It 'Correctly invokes a bash/sh command line via stdin (pipeline) and with pass-through arguments' {
      $cmd = 'ls -d "$1" | cat -n; echo "$2"'
      $cmdArgs = $HOME, 'hi'
      $expected = '1', $HOME, 'hi'
      -split ($cmd | ins - $cmdArgs) | Should -Be $expected
      -split ($cmd | ins -Args $cmdArgs) | Should -Be $expected
      -split ($cmd | ins -UseSh - $cmdArgs) | Should -Be $expected
      -split ($cmd | ins -UseSh -Args $cmdArgs) | Should -Be $expected
    }

    It 'Correctly passes pipeline (stdin) data to a bash/sh command line' {
      $data = 'foo', 'bar'
      $cmd = 'grep bar | cat -n'
      $cmdWithArg = 'grep "$1" | cat -n'
      $expected = '1', 'bar'

      -split ($data | ins $cmd) | Should -Be $expected
      -split ($data | ins -UseSh $cmd) | Should -Be $expected

      -split ($data | ins $cmdWithArg 'bar') | Should -Be $expected
      -split ($data | ins -UseSh $cmdWithArg 'bar') | Should -Be $expected

    }

    It 'A multi-line string with line continuations works as expected.' {
      $cmd = "printf '%s\n' a\`nb\`nc"
      $expected = 'abc'
      ins $cmd | Should -Be $expected
      ins -UseSh $cmd | Should -Be $expected
    }

    It 'A multi-line string with individual commands works as expected.' {
      $cmd = "ls -d /`necho hi"
      $expected = '/', 'hi'
      ins $cmd | Should -Be $expected
      $cmd | ins | Should -Be $expected
      ins -UseSh $cmd | Should -Be $expected
      $cmd | ins -UseSh | Should -Be $expected
    }

  }

}
