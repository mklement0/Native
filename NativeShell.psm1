Set-StrictMode -Version 1

# For older WinPS versions: set OS/edition flags (which PSCore automatically defines)
if (-not (Test-Path Variable:IsWindows)) { $IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $IsCoreCLR = $false }

# Test if a workaround for PowerShell's broken argument passing to external
# programs as described in
#   https://github.com/PowerShell/PowerShell/issues/1995
# is still required.
$needQuotingWorkaround = if ($IsWindows) {
  (choice.exe /d Y /t 0 /m 'Nat "King" Cole') -notmatch '"'
}
else {
  (printf %s '"ab"') -ne '"ab"'
}

Set-Alias ins Invoke-NativeShell

function Invoke-NativeShell {
  <#
.SYNOPSIS
Executes a native-shell command line. Alias name: ins

.DESCRIPTION
Executes a command line or ad-hoc script using the platform-native shell,
on Unix optionally with pass-through arguments.

.PARAMETER CommandLine
The command-line / script code to pass to the native shell for execution.

On Unix-like platforms, this parameter can also act as an ad-hoc script to 
which you may pass additional arguments.

.PARAMETER ArgumentList
Supported on Unix-like platforms only:

Any addtional arguments to pass through to the ad-hoc script passed to
-CommandLine.

Important:

* The *first* such argument is intepreted as the *name* of the script to
  be run (reflected in $0 inside the script). Therefore, it is the *second*
  such 
  If you don't care about this name, simply pass '-'

* If you pass the pass-through arguments *individually, positionally*, 
  precede them with an extra '--' argument to avoid conficts with PowerShell's
  common parameter names.

* If -CommandLine is bound *via the pipeline*, you *must* use -ArgumentList
  / -Args explicitly and specify the pass-through arguments *as an array*.

* On Windows, the command line isn't executed directly by cmd.exe, but via a
  a temporary *batch file*. This means that batch-file semantics will be in
  effect, notably needing %% rather than just % before `for` loop variables
  (e.g. %%i) and being able to escape a verbatim "%" as "%%"

.EXAMPLE
ins 'ver & date /t'

On Windows, (effectively) calls cmd.exe /c with the given command line,
which ouputs version information and the current date.

.EXAMPLE
'ver & date /t' | ins

Equivalent command using pipeline input to pass the command line.

.EXAMPLE
$msg = 'hi'; ins "echo $msg"

Uses string interpolation to incorporate a PowerShell variable value into
the native command line.

.EXAMPLE
ins 'ls / | cat -n'

On Unix, calls sh -c with the given command line,
which lists the files and directories in the root directory and numbers the
output lines.

.EXAMPLE
ins 'ls "$1" | cat -n; echo "$2"' -- - $HOME 'Hi there.'

Uses a pass-through argument to pass a PowerShell variable value to the 
native command line. Note the use of '--' to tell PowerShell that all 
remaining arguments are pass-through arguments and '-' as the first actual 
pass-through argument giving a *name* to the ad hoc script (command line).

.EXAMPLE
'ls "$1" | cat -n; echo "$2"' | ins -Args '-', $HOME, 'Hi there.'

Equivalent of the previous example with the command line passed via the
pipeline. Note the required use of -ArgumentList / -Args in that case, and
the need to specify the pass-through arguments as an *array*.

.NOTES

* On Unix-like platforms, /bin/sh is targeted as the native shell.

* On Windows, it is <systemRoot>\System32\cmd.exe, where <systemroot> is
  the Windows directory path as stored in the 'SystemRoot' registry value at
  'HKEY_LOCAL_MACHINE:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

#>

  [CmdletBinding(PositionalBinding = $false)]
  param(
    [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
    [string] $CommandLine
    ,
    [Parameter(ValueFromRemainingArguments)]
    [Alias('Args')]
    [string[]] $ArgumentList

  )

  begin {

    # On Windows, no additional arguments are supported.
    if ($IsWindows -and $ArgumentList.Count) {
      $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
          [System.PlatformNotSupportedException]::new("cmd.exe, the native Windows shell, doesn't support passing arguments to a command line."), 
          'PlatformNotSupportedException', 
          'InvalidArgument', 
          $null
        )
      )
    }
  
    $nativeShellExePath = if ($IsWindows) {
      # For increased robustness, rely on the SystemRoot definition (typically, C:\Windows)
      # from the registry rather than $env:ComSpec, given that the latter could
      # have been (more easily) modified, even in-process.
      '{0}\System32\cmd.exe' -f (Get-ItemPropertyValue -ErrorAction Stop -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' SystemRoot)
    }
    else {
      # The de-facto standard location for the default system shell on Unix-like platforms.
      '/bin/sh'
    }

    # On Windows, we use a temporary batch file to avoid re-quoting problems 
    # that would arise if the command line were passed to cmd /c as an *argument*.
    if ($IsWindows) {
      $tmpBatchFile = New-TemporaryFile -ErrorAction Stop
    }

  }

  process {

    if ($IsWindows) {

      # Write the command line to the temp. batch file.
      # Use UTF-16 to avoid encoding problems.
      Set-Content -Encoding Unicode -LiteralPath $tmpBatchFile -Value $CommandLine

      & $nativeShellExePath /c $tmpBatchFile

    }
    else {

      if ($script:needQuotingWorkaround) {
        inp $nativeShellExePath -c $CommandLine $ArgumentList
      }
      else {
        & $nativeShellExePath -c $CommandLine $ArgumentList
      }

    }

  }

  end {
    if ($IsWindows) {
      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile
    }
  }
}

function inp {
  <#
.SYNOPSIS
Invokes native programs robustly.

.DESCRIPTION
Invokes native programs (which includes script files and batch files) with 
arguments passed through properly.

IMPORTANT: 

* The only reason for this function's existence is that up to at least
    PowerShell 7.0, arguments passed to native programs are not passed
    correctly if they are either the empty string or have embedded double quotes.
    Should the underlying problem ever be fixed in PowerShell itself, this
    function will no longer apply its workarounds and effectively act like '&', the call
    operator. See the NOTES section for more information.

    * This function is intentially designed to be a minimalist stopgap that
    should be unobtrusive and simple to use. It is therefore implemented as 
    a *simple* function and does *not* support common parameters (just like
    you can't use common parameters with direct invocation).

Simply invoke a native program as you normally would, except prefixed with
'inp' as the executable name (if invocation via call operator '&' would
normally be necessary, use 'inp' *instead* of it); e.g.:

  inp 

CAVEATS:

  * While $LASTEXITCODE is set as usual, $? always ends up as $true.
    Query $LASTEXITCODE only to infer success vs. failure.

  * This function should work robustly PowerShell Core, but in
    Windows PowerShell you still have edge cases with embedded double quotes
    that break if `\"` escaping (rather than `""`) must be used behind the
    scenes; whether `\"` is needed is derived from the specific target
    executable being invoked.


.EXAMPLE
inp echoArgs.exe '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'

Calls the echoArgs.exe executable, which echoes the individual arguments it
receives in diagnostic form:

    Arg 0 is <>
    Arg 1 is <a&b>
    Arg 2 is <3" of snow>
    Arg 3 is <Nat "King" Cole>
    Arg 4 is <c:\temp 1\>
    Arg 5 is <a \" b>

    Command line:
    "C:\ProgramData\chocolatey\lib\echoargs\tools\EchoArgs.exe" "" a&b "3\" of snow" "Nat \"King\" Cole" "c:\temp 1\\" "a \\\" b"

Note: echoArgs.exe is installable via Chocolatey using the following commmand
from an elevated session:

    choco install echoargs -y 

.NOTES

For background information on the broken argument handling, see:
https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606

#>
  # Split into executable name/path and arguments.
  $exe, $argsForExe = $args

  # Resolve to the underlying command (if it's an alias) and ensure that an external executable was specified.
  $app = Get-Command -ErrorAction Stop $exe
  if ($app.ResolvedCommand) { $app = $app.ResolvedCommand }
  if ($app.CommandType -ne 'Application') { Throw "Not an external program, non-PS script, or batch file: $exe" }

  # IF THE WORKAROUND IS NO LONGER NEEDED, invoke the command as-is and return.
  if (-not $needQuotingWorkaround) {
    return & $exe $argsForExe
  }

  if ($argsForExe.Count -eq 0) {
    # Argument-less invocation - no extra work needed.
    & $exe
  }
  else {
    # Invocation with arguments: escape them properly to pass them through as literals.
    # Decide whether to escape embedded double quotes as \" or as "", based on the target executable.
    # * On Unix-like platforms, we always use \"
    # * On Windows, we use "" where we know it's safe to do. cmd.exe / batch files require "", and Microsoft compiler-generated executables do too, often in addition to supporting \",
    #   notably including Python and Node.js
    #   However, notable interpreters that support \" ONLY are Ruby and Perl (as well as PowerShell's own CLI, but it's better to call that with a script block from within PowerShell).
    #   Targeting a batch file triggers "" escaping, but in the case of stub batch files that simply relay to a different executable, that could still break
    #   if the ultimate target executable only supports \"
    $useDoubledDoubleQuotes = $IsWindows -and ($app.Source -match '[/\\]?(?<exe>cmd|msiexec)(?:\.exe)?$' -or $app.Source -match '\.(?<ext>cmd|bat|py|pyw)$')
    $doubleQuoteEscapeSequence = ('\"', '""')[$useDoubledDoubleQuotes]
    $isMsiExec = $useDoubledDoubleQuotes -and $Matches['exe'] -eq 'msiexec'
    $isCmd = $useDoubledDoubleQuotes -and ($Matches['exe'] -eq 'cmd' -or $Matches['ext'] -in 'cmd', 'bat')
    $escapedArgs = foreach ($potentialArrayArg in $argsForExe) {
      foreach ($arg in $potentialArrayArg) { # To support invocations such as `inp $someArray foo bar`, i.e.. a mix of array-splatting and indiv. args.
        if ($arg -isnot [string]) { $arg = "$arg" } # Make sure that each argument is a string.
        if ('' -eq $arg) { '""'; continue } # Empty arguments must be passed as `'""'`(!), otherwise they are omitted.
        $hasDoubleQuotes = $arg.Contains('"')
        $hasSpaces = $arg.Contains(' ')
        if ($hasDoubleQuotes) {
          # First, always double any preexisting `\` instances before embedded `"` chars.
          # so that `\"` isn't interpreted as an escaped `"`.
          $arg = $arg -replace '(\\+)"', '$1$1"'
          # Then, escape the embedded `"` chars. either as `\"` or as `""`.
          # If \" escaping is used:
          # * In PS Core, use of `\"` is safe, because its use triggers enclosing double-quoting (if spaces are also present).
          # * !! In WinPS, sadly, that isn't true, so something like `'foo="bar none"'` results in `foo=\"bar none\"` -
          #   !! which - due to the lack of enclosing "..." - is seen as *2* arguments by the target app, `foo="bar` and `none"`.
          #   !! Similarly, '3" of snow' would result in `3\" of snow`, which the target app receives as *3* arguments, `3"`, `of`, and `snow`.
          #   !! Even manually enclosing the value in *embedded* " doesn't help, because that then triggers *additional* double-quoting.
          $arg = $arg -replace '"', $doubleQuoteEscapeSequence
        }
        elseif ($isMsiExec -and $arg -match '^(\w+)=(.* .*)$') {
          # An msiexec argument originally passed in the form `PROP="value with spaces"`, which PowerShell turned into `PROP=value with spaces`
          # This would be passed as `"PROP=value with spaces"`, which msiexec, sady, doesn't recognize (`PROP=valueWithoutSpaces` works fine, however).
          # We reconstruct the form `PROP="value with spaces"`, which both WinPS And PS Core pass through as-is.
          $arg = '{0}="{1}"' -f $Matches[1], $Matches[2]
        }
        # As a courtesy, enclose arguments that PowerShell would pass unquoted in "...",
        # if they contain cmd.exe metachars. that would break calls to cmd.exe / batch files.
        # Note: Leaving the argument unquoted and instead individually ^-escaping the cmd.exe metacharacters
        #       is ultimately NOT the right solution, because the presence of such an argument breaks pass-through
        #       invocations with %*, which is the most important scenario we want to support.
        $manuallyEscapeForCmd = $isCmd -and -not $hasSpaces -and $arg -match '[&|<>^,;]'
        # In WinPS, double trailing `\` instances in arguments that have spaces and will therefore be "..."-enclosed,
        # so that `\"` isn't mistaken for an escaped `"` - in PS Core, this escaping happens automatically.
        if (-not $IsCoreCLR -and ($hasSpaces -or $manuallyEscapeForCmd) -and $arg -match '\\') {
          $arg = $arg -replace '\\+$', '$&$&'
        }
        if ($manuallyEscapeForCmd) {
          # Wrap in *embedded* enclosing double quotes, which both WinPS and PS Core pass through as-is.
          $arg = '"' + $arg + '"'
        }
        $arg
      }
    }
    # Invoke the executable with the properly escaped arguments.
    & $exe $escapedArgs
  }
}
