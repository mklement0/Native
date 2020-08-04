### 
# IMPORTANT: KEEP THIS MODULE PSv3-COMPATIBLE.
# Notably:
#   * do not use .ForEach() / .Where()
#   * do not use ::new()
#   * do not use Get-ItemPropertyValue
#   * do not use New-TemporaryFile
### 

Set-StrictMode -Version 1

#region Define the ALIASES to EXPORT (must be referenced in the *.psd1 file).
Set-Alias ins Invoke-NativeShell
Set-Alias dbea Debug-ExecutableArguments
# Note: 'ie'  and 'iet' are *directly* used as the *function* names,
#       deliberately forgoing verbose names, for the reasons explained
#       in the comment-based help for 'ie'.
#endregion

# For older WinPS versions: set OS/edition flags (which in PSCore are automatically defined).
if (-not (Test-Path Variable:IsWindows)) { $IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $IsCoreCLR = $false }

# Test if a workaround for PowerShell's broken argument passing to external
# programs as described in
#   https://github.com/PowerShell/PowerShell/issues/1995
# is still required.
$script:needQuotingWorkaround = if ($IsWindows) {
  (choice.exe /d Y /t 0 /m 'Nat "King" Cole') -notmatch '"'
}
else {
  (printf %s '"ab"') -ne '"ab"'
}

#region Define the FUNCTIONS to EXPORT (must be referenced in the *.psd1 file)

function Invoke-NativeShell {
  <#
.SYNOPSIS
Executes a native shell command line. Aliased to: ins

.DESCRIPTION
Executes a command line or ad-hoc script using the platform-native shell,
on Unix optionally with pass-through arguments.

If no argument and no pipeline input is given, an interactive shell is entered.

Pipeline input is supported in two fundamental modes:

* The pipeline is the *command line* to execute:

  * In this case, no -CommandLine argument must be passed, or, if pass-through
    arguments are specified (Unix only), it must be '-' to explicitly signal 
    that the command line is coming from the pipeline (stdin).

* The pipeline is *data* to pass *to* the command line to execute:

  * In this case, the command line must be passed via -CommandLine.

NOTE: 

* By definition, such calls will be *platform-specific*.
  To perform platform-agnostic calls to a single native executable, use the
  'ie' function that comes with this module.

* On Unix-like platforms, /bin/bash is used by default, due to its ubiquity.
  If instead you want to use the official system default shell, /bin/sh, which
  typically supports fewer features than Bash, pass -UseSh

* The native shell's exit code will be reflected in $LASTEXITCODE; use only 
  $LASTEXITCODE to infer success vs. failure, not $?, which always ends up 
  $true.

* When /bin/bash and /bin/sh accept a command line as a CLI argument, it is via 
  the -c option, with subsequent positional arguments getting passed 
  *to the command line* being invoked; curiously, however, the first such 
  argument sets the invocation name that the command line sees as special 
  parameter $0; it is only the *second* subsequent argument that becomes $1, 
  the first true argument.
  Since this is somewhat counterintuitive and since setting $0 in this scenaro 
  is rarely, if ever, needed, this function leaves $0 at its default and passes
  any pass-through arguments starting as parameter $1.

.PARAMETER CommandLine
The command line to pass to the native shell for execution.

On Unix-like platforms, this parameter can also act as an ad-hoc script to 
which you may pass additional arguments that the script sees as
parameter $1, ...

You may omit this parameter and pass the command line via the pipeline instead.
If you use the pipeline this way on Unix and you additionally want to specify
pass-through arguments positionally, you can pass '-' as the -CommandLine
argument to signal that the code is specified via the pipeline; alternatively,
use the -ArgumentList / -Args parameter explicitly, which necessitates passing
the arguments as an *array*.

IMPORTANT:
  On Windows, the command line isn't executed directly by cmd.exe, 
  but via a temporary *batch file*. This means that batch-file semantics rather
  than command-prompt semantics will be in effect, notably needing %% rather 
  than just % before `for` loop variables (e.g. %%i) and being able to escape
  verbatim "%" characters as "%%"

.PARAMETER ArgumentList
Supported on Unix-like platforms only:

Any addtional arguments to pass through to the ad-hoc script passed to
-CommandLine.

Important:

* As stated, these arguments bind to the standard bash/sh parameters starting
  with $1.

* If you pass the pass-through arguments *individually, positionally*, 
  you may precede them with an extra '--' argument to avoid name conflicts with
  this function's own parameters (which includes the supported common parameters).

* If the command line is supplied via the pipeline, you must either pass '-'
  as -CommandLine or use -ArgumentList / -Args explicitly and specify the 
  pass-through arguments *as an array*.

.PARAMETER InputObject
An auxiliary parameter required for technical reasons.
Do not use it directly.

.EXAMPLE
ins 'ver & date /t'

On Windows, calls cmd.exe with the given command line,
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

On Unix, calls Bash with the given command line,
which lists the files and directories in the root directory and numbers the
output lines.

.EXAMPLE
ins 'ls "$1" | cat -n; echo "$2"' $HOME 'Hi there.'

Uses a pass-through argument to pass a PowerShell variable value to the 
native command line. Note the use of '-' as the first pass-through argument,
which determines the *name* of the ad hoc script, as reflected in $0.
The second argument becomes $1, and so on.

.EXAMPLE
'ls "$1" | cat -n; echo "$2"' | ins -UseSh - $HOME 'Hi there.'

Equivalent of the previous example with the command line passed via the
pipeline, except that /bin/sh is used for execution.
Note that since the command line is provided via the pipeline and there are
pass-through arguments present, '-' must be passed as the -CommandLine argument.

.EXAMPLE
'one', 'two', 'three' | ins 'grep three | cat -n'

Sends data through the pipeline to pass to the native command line as stdin
input.

.NOTES

* On Unix-like platforms, /bin/bash is targeted by default; if -UseSh is
  specified or /bin/bash doesn't exist, /bin/sh is used.

* On Windows, it is <systemRoot>\System32\cmd.exe, where <systemroot> is
  the Windows directory path as stored in the 'SystemRoot' registry value at
  'HKEY_LOCAL_MACHINE:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

#>

  [CmdletBinding(PositionalBinding = $false)]
  param(
    [Parameter(Position = 1)]
    [string] $CommandLine
    ,
    [Parameter(ValueFromRemainingArguments = $true)]
    [Alias('Args')]
    [string[]] $ArgumentList
    ,
    [switch] $UseSh
    ,
    [Parameter(ValueFromPipeline = $true)] # Dummy parameter to ensure that pipeline input is accepted, even though we use $input to process it.
    $InputObject
  )

  # On Windows, no additional arguments are supported.
  if ($IsWindows -and $ArgumentList.Count) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
        [System.PlatformNotSupportedException] "cmd.exe, the native Windows shell, doesn't support passing arguments to a command line.", 
        'PlatformNotSupportedException', 
        'InvalidArgument', 
        'cmd.exe'
      ))
    )
  }
  
  $nativeShellExePath = if ($IsWindows) {
    # For increased robustness, rely on the SystemRoot definition (typically, C:\Windows)
    # from the registry rather than $env:ComSpec, given that the latter could
    # have been (more easily) modified, even in-process.
    '{0}\System32\cmd.exe' -f $(try {
        (Get-Item -ErrorAction Stop -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').GetValue('SystemRoot', 'C:\Windows')
      }
      catch {
        'C:\Windows'
      })
  }
  else {
    # Note: By default, due to its ubiquity, we try /bin/bash, unless -UseSh was passed.
    if ($UseSh -or -not (Test-Path -PathType Leaf '/bin/bash')) {
      # The de-facto standard location for the default system shell on Unix-like platforms.
      '/bin/sh'
    }
    else {
      '/bin/bash'
    }
  }

  $havePipelineInput = $MyInvocation.ExpectingInput
  $pipelineInputIsCommandLine = $havePipelineInput -and (-not $CommandLine -or $CommandLine -eq '-')

  # If neither a command line nor pipeline input is given, enter an interactive
  # session of the target shell.
  if (-not $havePipelineInput -and -not $CommandLine) { 

    Write-Verbose "Entering an interactive $nativeShellExePath session..."
    & $nativeShellExePath; return 

  }
  elseif ($pipelineInputIsCommandLine) {

    Write-Verbose "Executing via $nativeShellExePath..."

    $passThruArgs = if ($ArgumentList.Count) {
      # If arguments are also passed, Bash / sh require -s as the explicit 
      # signal that the script code is being passed via the pipeline (stdin).
      , '-s' + $ArgumentList
    }
    else {
      @()
    }

    $input | & $nativeShellExePath $passThruArgs

  }
  else {
    # $CommandLine with actual code given, possibly combined with *data* pipeline input.

    # On Windows, we use a temporary batch file to avoid re-quoting problems 
    # that would arise if the command line were passed to cmd /c as an *argument*.
    if ($IsWindows) {

      $tmpBatchFile = [IO.Path]::GetTempFileName() + '.cmd'

      # Write the command line to the temp. batch file.
      Set-Content -Encoding Oem -LiteralPath $tmpBatchFile -Value "@$CommandLine"

      # Note: For predictability, we use explicit switches in order to get what should be the default
      #       behavior of cmd.exe on a pristine system:
      #       /d == no auto-run, /e:on == enable command extensions; /v:off == disable delayed variable expansion
      $input | & $nativeShellExePath /d /e:on /v:off /c $tmpBatchFile

      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile

    }
    else {
      # Unix

      $passThruArgs = if ($ArgumentList.Count) {
        # POSIX-like shells interpret the first post `-c <code>` operand as $0,
        # which is both unexpected and rarely useful.
        # We abstract this behavior away by emulating the default $0 value (the
        # name/path of the shell being invoked) and by passing the 
        # the pass-through arguments starting with $1.
        , $nativeShellExePath + $ArgumentList
      }
      else {
        @()
      }
  
      if ($script:needQuotingWorkaround) {
        $input | ie $nativeShellExePath -c $CommandLine $passThruArgs
      }
      else {
        $input | & $nativeShellExePath -c $CommandLine $passThruArgs
      }

    }


  }

}

function ie {
  <#
.SYNOPSIS
Invokes an external executable with robust argument passing.

.DESCRIPTION
Invokes an external executable with arguments passed through properly, even if
they contain embedded double quotes or they're the empty string.

'ie' stands for 'Invoke (External) Executable'. The related 'iet' wrapper
function additionally throws an error if the external executable indicated
failure via a nonzero process exit code.

Note: Since the invocation solely relies on PowerShell's own argument-mode
      syntax and since no other shell is involved (as in a direct call),
      this function is suitable for use in *cross-platform*  code, unlike calls
      to Invoke-NativeShell / ins.

Use this function by simply prefixing a call to an external executable with
'ie' as the executable (if invocation via call operator '&' would
normally be necessary, use 'ie' *instead* of it). E.g., on Unix:

  ie printf '"%s" ' print these arguments quoted

IMPORTANT: 

* On Windows, this function also handles special quoting needs for 
  msiexec.exe / msdeploy.exe and batch files, so there should generally be no 
  need for --%, the stop-parsing symbol - which this function does *not* support.
  In other words: EITHER use this function OR, if you truly need --%, use it
  with direct invocation only.

* External executable in this context means any executable that PowerShell must
  invoke via a child process, which encompasses not just binary executables,
  but also batch files and other shells' or scripting languages' scripts.

* The only reason for this function's existence is that up to at least
  PowerShell 7.0, arguments passed to external programs are not passed
  correctly if they are either the empty string or have embedded double quotes.
  Should the underlying problem ever be fixed in PowerShell itself, this
  function will no longer apply its workarounds and will effectively act like 
  '&', the call operator. See the NOTES section for a link to more information.

* This function is intentially designed to be a minimalist stopgap that
  should be unobtrusive and simple to use. It is therefore implemented as 
  a *simple* function and does *not* support common parameters (just like
  you can't use common parameters with direct invocation).

CAVEATS:

  * While $LASTEXITCODE is set as usual, $? always ends up as $true.
    Only query $LASTEXITCODE to infer success vs. failure.

  * This function should work robustly in PowerShell Core, but in
    Windows PowerShell there are still edge cases with embedded double quotes
    that break if `\"` escaping (rather than `""`) must be used behind the
    scenes; whether `\"` must be used is inferred from the specific target
    executable being invoked.

.EXAMPLE
ie echoArgs.exe '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'

Calls the echoArgs.exe executable on Windows, which echoes the individual 
arguments it receives in diagnostic form as follows, showing that the arguments
were passed as intended:

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
  # Note: We can't assume that $argsForExe will be a flat array - see below.
  $exe, $argsForExe = $args

  if (-not $exe) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
        [System.Management.Automation.ParameterBindingException] "Missing mandary parameter: Please specify the external executable to invoke.",
        'MissingMandatoryParameter',
        'InvalidArgument',
        $null
      ))
    )
  }

  # Resolve to the underlying command (if it's an alias) and ensure that an external executable was specified.
  $app = try { Get-Command -ErrorAction Stop $exe } catch { throw }
  if ($app -and $app.ResolvedCommand) { $app = $app.ResolvedCommand }
  if ($app.CommandType -ne 'Application') {
    $exeDescr = '"{0}"' -f $exe
    if ($exe -ne "$app") { $exeDescr += ' ("{0}")' -f "$app" }
    # Throw "This command supports external executables only; $exeDescr isn't one." 
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
        [ArgumentException] "This command supports external executables (applications) only; $exeDescr is a command of type $($app.CommandType)",
        'InvalidCommandType',
        'InvalidArgument',
        $exe
      ))
    ) 
    # Note: 
    #  * Even if we wanted to support calls to PowerShell-native commands too, 
    #    we can't, given that this simple function is based on the array of positional arguments, $args. 
    #    While @args is built-in magic for passing even *named* arguments through,
    #    we need to split $args into executable name and remaining arguments here, and the magic doesn't work with custom arrays.
  }
  
  # Use the full path for invocation, to avoid having to re-resolve the executable as specified to the underlying full path.
  #  Note: Regrettably, Get-Command also reports *documents* as commands of type 'Application' - see https://github.com/PowerShell/PowerShell/issues/12625
  #        While we could do our own subsequent analysis to see if a true executable was specified, that doesn't seem worth the trouble.
  #        It's usually pointless to invoke a document directly *with additional arguments*, which are usually ignored.
  $exe = $app.Path

  # Flatten the array of arguments, because we also want to support invocations such as `ie $someArray foo bar`, 
  # i.e. a mix of array-splatting and indiv. args.
  $argsForExe = foreach ($potentialArrayArg in $argsForExe) { foreach ($arg in $potentialArrayArg) { $arg } }

  # See if a PowerShell CLI is being invoked, so we can detect whether a *script block* is among the arguments,
  # which causes PowerShell to transform the invocation into a Base64-encoded one using the -encodedCommand CLI parameter.
  $isPsCli = $exe -match '[\\/](?:pwsh|powershell)(?:\.exe)?$'

  # Construct the array of escaped arguments, if necessary.
  # Note: We cannot use .ForEach('GetType'), because we must remain PSv3-compatible.
  [array] $escapedArgs = 
  if ($null -eq $argsForExe) {
    # To be safe: If there are no arguments to pass, use an *empty array* for splatting so as
    #             to be sure that *no* arguments are passed. We don't want to rely on passing $null
    #             getting that same treatment in all future PS versions.
    @()
  }
  elseif (-not $script:needQuotingWorkaround -or ($isPsCli -and $(foreach ($el in $argsForExe) { if ($el -is [scriptblock]) { $true; break } }))) {
  
    # Use the array as-is if (a) the quoting workaround is no longer needed or (b) the engine itself will aply Base64-encoding behind the scenes
    # using the -encodedCommand CLI parameter.
    # Note: As of PowerShell Core 7.1.0-preview.5, the engine unexpectedly applies Base64-encoding in the presence of a [scriptblock] argument alone,
    #       irrespective of what executable is being invoked: see https://github.com/PowerShell/PowerShell/issues/4973
    #       In effect we're masking the bug by exhibiting more sensible behavior if the executable is NOT a PowerShell CLI (stringified script block, which may still not be the intent),
    #       in the hopes that the bug will get fixed and that direct execution will then exhibit the same behavior.
    $argsForExe
  
  }
  else {

    # Escape arguments properly properly to pass them through as seen verbatim by PowerShell.
    # Decide whether to escape embedded double quotes as \" or as "", based on the target executable.
    # * On Unix-like platforms, we always use \"
    # * On Windows, we use "" where we know it's safe to do. cmd.exe / batch files require "", and Microsoft compiler-generated executables do too, often in addition to supporting \",
    #   notably including Python and Node.js
    #   However, notable interpreters that support \" ONLY are Ruby and Perl (as well as PowerShell's own CLI, but it's better to call that with a script block from within PowerShell).
    #   Targeting a batch file triggers "" escaping, but note that in the case of stub batch files that simply relay to a different executable, that could still break
    #   if the ultimate target executable only supports \"
    $useDoubledDoubleQuotes = $IsWindows -and ($app.Source -match '[/\\]?(?<exe>cmd|msiexec|msdeploy)(?:\.exe)?$' -or $app.Source -match '\.(?<ext>cmd|bat|py|pyw)$')
    $doubleQuoteEscapeSequence = ('\"', '""')[$useDoubledDoubleQuotes]
    $isMsiStyleExe = $useDoubledDoubleQuotes -and $Matches['exe'] -in 'msiexec', 'msdeploy'
    $isBatchFile = $useDoubledDoubleQuotes -and $Matches['ext'] -in 'cmd', 'bat'

    foreach ($arg in $argsForExe) {
      if ($arg -isnot [string]) {
        $arg = "$arg"  # Make sure that each argument is a string, so we can analyze the the string representation with respect to quoting.
      }
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
      elseif ($isMsiStyleExe -and $arg -match '^(\w+)=(.* .*)$') {
        # An msiexec / msdeploy argument originally passed in the form `PROP="value with spaces"`, which PowerShell turned into `PROP=value with spaces`
        # This would be passed as `"PROP=value with spaces"`, which these programs, sadly, don't recognize (`PROP=valueWithoutSpaces` works fine, however).
        # We reconstruct the form `PROP="value with spaces"`, which both WinPS And PS Core pass through as-is.
        $arg = '{0}="{1}"' -f $Matches[1], $Matches[2]
      }
      # For batch files, explicitly enclose in "..." those arguments that PowerShell would pass unquoted due to absence of whitespace
      # *if they contain cmd.exe metachars.* Given that cmd.exe regrettably subjects batch-file arguments to its usual parsing even 
      # when *not* calling from inside cmd.exe, unquoted arguments such as `a&b` would *break* the call.      
      # Note: * Leaving the argument unquoted and instead individually ^-escaping the cmd.exe metacharacters
      #         is ultimately NOT the right solution, because the presence of such an argument breaks pass-through
      #         invocations with %*, which is the most important scenario we want to support.
      #       * Also, we do not perform this explicitly quoting for calls *directly to cmd.exe*, as the reasonable assumption
      #         there is that cmd.exe metacharacters then *should* have their usual, syntactic meaning (even though the problem
      #         would only arise in awkwardly formatted commands such as (from PowerShell) `cmd /c 'ver|findstr' V`. Ultimately,
      #         it seems that the point is moot, because - like PowerShell - `cmd.exe /c` seems to strip enclosing double quotes from
      #         individual arguments before interpreting the space-concatenated list of stripped arguments like a submitted-from-inside-cmd.exe
      #         command line.
      $manuallyEscapeForCmd = $isBatchFile -and -not $hasSpaces -and $arg -match '[&|<>^,;]'
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

  # Invoke the executable with the properly escaped arguments, if any, possibly with pipeline input.  
  # Note: We must use @escapedArgs rather than $escapedArgs, otherwise PowerShell won't apply
  #       Base64 encoding in the presence of a script-block argument when its CLI is called.
  #       Use of @ also results in --% getting removed, but we don't support it meaningfully anyway.
  $input | & $exe @escapedArgs

}

function iet {
  <#
.SYNOPSIS
Invokes an external executable robustly and throws an error if its exit code is 
nonzero.

.DESCRIPTION
Like the 'ie' function it wraps, this function invokes an external executable 
with robust argument passing and additionally throws a script-terminating error
if the executable reports a nonzero process exit code (as reflected in the 
automatic $LASTEXITCODE variable).

NOTE: This function only works meaningfully with *console* (terminal) programs, 
      because only they run synchronously, which ensures that their exit code 
      is already known when the invocation returns.

.EXAMPLE
iet curl.exe -u jdoe 'https://api.github.com/user/repos' -d '{ "name": "foo"}'

Invokes the external curl utility to create a new GitHub repo.
If doing so fails, as indicated by curl's process exit code being nonzero,
an script-terminating error is thrown.

.NOTES

Once the following RFC is implemented, you'll be able to use a preference
variable to control how nonzero exit codes reported by external programs are
handled:

https://github.com/PowerShell/PowerShell-RFC/pull/88

#>

  $Input | ie @args

  if ($LASTEXITCODE) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
        [System.Management.Automation.ApplicationFailedException] "`"$($args[0])`" terminated with nonzero exit code $LASTEXITCODE.",
        'NativeCommandError',
        'OperationStopped',
        "$args"  # Report the full command, though note that this is just a space-separated list of the verbatim arguments, without quoting and escaping.
      ))
    )
  }

}

function Debug-ExecutableArguments {
  <#
.SYNOPSIS
Debugs Executable Argument passing.

.DESCRIPTION
Acts as an external executable that prints the arguments passed to it in 
diagnostic form, similar to what the well-known third-party echoArgs.exe 
utility does on Windows.

On Windows, the whole command line is printed as well.
On Unix, there is no point in doing so, as processes there do not receive a
single command line that encodes all arguments, but an array of verbatim
strings.

The output is a single, multi-line string formatted for easy readability by
humans.

This function is useful for diagnosing the problems with passing empty-string
arguments and arguments with embedded double quotes to external executables
that exist up to at least v7.0 and are detailed here:

https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606

You can avoid these problems altogether if you use the 'ie' function to call
external executables.

A helper executable (Windows) / shell script (Unix), created on demand, is used
behind the scenes to receive and print the given arguments.

On Windows, you can specify -UseBatchFile to use a batch file instead, or
-UseWrapperBatchFile to use an intermediate batch file to pass the arguments
through to the helper binary.

.PARAMETER ArgumentList
The arguments to pass - either with -ArgumentList / -Args as an *array*,
or more conveniently, as *individual*, positional arguments.

That is, the following two invocations are equivalent:

  Debug-ExecutableArguments one, two, three

and:

  Debug-ExecutableArguments one two three

In the latter form, in the unlikely event that you need to disambiguate
pass-through arguments from the parameters supported by this command itself,
prepend the pass-through arguments with a '--' argument; e.g., to pass
'-UseBatchFile` as a pass-through argument:

  Debug-ExecutableArguments -- -UseBatchFile one two three

.PARAMETER UseBatchFile
On Windows, uses a batch file rather than the helper binary to print the 
arguments it receives in diagnostic form.

Note that batch-file arguments are subject to cmd.exe's usual parsing rules.

.PARAMETER UseWrapperBatchFile
On Windows, uses an *intermediate* batch file that passes the
arguments it receives *through* to the helper binary.

This is useful for testing how CLIs that use a wrapper batch file as their 
entry point ultimately receive arguments. The Azure CLI is a prominent
example.

.EXAMPLE
Debug-ExecutableArguments -u '' 'https://api.github.com/user/repos' -d '{ "name": "foo" }'

On Unix, you'll see the following output as of v7.0:

  4 argument(s) received (enclosed in <...> for delineation):

    <-u>
    <https://api.github.com/user/repos>
    <-d>
    <{ name: foo }>

Note the missing empty-string argument and the loss of the embedded " chars.

On Windows, you'll additionally see the following as of v7.0:

  Command line (executable omitted):
    -u https://api.github.com/user/repos -d "{ "name": "foo" }"

The command line shows that the empty-argument string was never passed, and
the lack of escaping the embedded " chars., when the argument was re-quoted
behind the scenes to use double quotes, resulted in their effective removal
(because the argument was intrepreted as a composite string composed of
double-quoted and unquoted parts).

.NOTES

On Windows, a helper executable is created on demand in the following location:

  $env:TEMP\f7fd420a-47e4-4216-bd57-c88696123608\dbea.exe

You can delete it anytime, but note that you'll pay a performance penalty for
the re-creation on the next invocation.

#>

  [CmdletBinding(PositionalBinding = $false)]
  param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [Alias('Args')]
    $ArgumentList
    ,
    [switch] $UseBatchFile
    ,
    [switch] $UseWrapperBatchFile
  )
  
  if (($UseBatchFile -or $UseWrapperBatchFile) -and -not $IsWindows) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
        [System.PlatformNotSupportedException] "The -UseBatchFile and -UseWrapperBatchFile parameters are supported on Windows only.", 
        'PlatformNotSupportedException', 
        'InvalidArgument', 
        $null
      ))
    )
  }
      
  if ($IsWindows) {
    
    # Note: Unless explicitly requested to use a batch file only, we need a 
    #       binary helper executable to robustly replicate what external executables 
    #       will receive as arguments, so we create a .NET console application on demand, 
    #       using inline C# code.
    #       Note: This application will invariably recognize "" as an alternative to \"
    #             escaping, which most, but not all CLIs on Windows do.
    $helperBinary = if (-not $UseBatchFile) { get-WinHelperBinaryPath }

    if ($UseBatchFile -or $UseWrapperBatchFile) {
  
      $tmpBatchFile = [IO.Path]::GetTempFileName() + '.cmd'
    
      $content = if ($UseWrapperBatchFile) {
        # The wrapper batch file simply passes all args through to the helper binary.
        "@$helperBinary %*"
        Write-Verbose "Executing helper binary `"$helperBinary`" via temporary wrapper batch file `"$tmpBatchFile`""
      }
      else {
        # Create the argument-echoing batch file on demand.
        @'
    @echo off
    setlocal
    
    call :count_args %*
    echo %ReturnValue% argument(s) received (enclosed in ^<...^> for delineation):
    echo.
    
    :for_arg
    
      if %1.==. goto for_arg_done
    
      echo   ^<%1^>
    
      shift
    goto for_arg
    :for_arg_done
    
    echo.
    
    goto :eof
    
    :count_args
      set /a ReturnValue = 0
      :count_args_for
    
        if %1.==. goto :eof
    
        set /a ReturnValue += 1
    
        shift
      goto count_args_for
'@
        Write-Verbose "Executing argument-echoing batch file: $tmpBatchFile"
      }

      Set-Content -Encoding Oem -LiteralPath $tmpBatchFile -Value $content
    
      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because we want to support --%, the stop-parsing symbol.
      & $tmpBatchFile @ArgumentList
    
      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile
    
    }
    else {
      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because (on Windows) we want to support --%, the stop-parsing symbol.
      Write-Verbose "Executing helper binary: $helperBinary"
      & $helperBinary @ArgumentList
    }

  }
  else {
    # Unix

    Write-Verbose "Executing ad-hoc in-memory /bin/sh script."

    # No need for a binary executable - a shell script will do.
    # Note: For consistency, and since --% is technically (albeit mostly uselessly)
    #       supported on Unix too, we also use @ArgumentList rather than $ArgumentList on Unix.
    @'
printf '%s\n\n' "$# argument(s) passed (enclosed in <...> for delineation):"

for a; do 
  printf '%s\n' "  <$a>"
done

printf '%s\n'
'@ | /bin/sh -s -- @ArgumentList

  }

}

#endregion Functions to export

# Internal Windows-only function that returns the path to the helper binary, 
# which is created on demand.
function get-WinHelperBinaryPath() {

  # Create a unique temp. dir. Note: the GUID is the one from the *.psd1 file
  # and is assumed not to change.
  $dir = Join-Path $env:TEMP 'f7fd420a-47e4-4216-bd57-c88696123608'
  $null = New-Item -ErrorAction Stop -Force -Type Directory $dir

  $exePath = "$dir\dbea.exe" # Use the alias name as the base file name.

  # If the executable already doesn't exist yet or is older than this module,
  # (re)create it.
  $itm = Get-Item -LiteralPath $exePath -ErrorAction Ignore
  $mustCreate = -not $itm -or $itm.LastWriteTime -lt (Get-Item -LiteralPath $PSCommandPath).LastWriteTime

  if ($mustCreate) {
    Write-Verbose "Creating helper binary: $exePath"
    if ($itm) { Remove-Item -ErrorAction Stop -Force -LiteralPath $exePath }
    # Define a script block that creates the binary via Add-Type -OutputType ConsoleApplication
    # from inline C# code.
    # IMPORTANT: Since in PS Core the script block must be passed to the WinPS CLI (see below),
    #            it *must not contain references to the caller's variables*, except via *parameters*.
    $sb = { 
      param([string] $exePath)

      Add-Type -ErrorAction Stop -OutputType ConsoleApplication -OutputAssembly $exePath -TypeDefinition @'
using System;
using System.Text.RegularExpressions;

static class ConsoleApp {
  static int Main(string[] args) {

    Console.WriteLine("{0} argument(s) received (enclosed in <...> for delineation):\n", args.Length);

    for (int i = 0; i < args.Length; ++i) {
      Console.WriteLine("  <{0}>", args[i]);
    }

    // Get the full command line and strip the executable (which is always the
    // full, double-quoted path, based on how PowerShell executes external programs).
    string cmdLine = Environment.CommandLine;
    cmdLine = cmdLine.Substring(Regex.Match(cmdLine, "\".+?\"").Value.Length).TrimStart();

    Console.WriteLine("\nCommand line (executable omitted):\n\n  {0}\n", cmdLine);

    return 0;
  }
}
'@
    }
    if ($IsCoreCLR) {
      # !! As of PowerShell Core 7.1.0-preview.5, -OutputType ConsoleApplication produces
      # !! broken executables in PowerShel *Core* - see https://github.com/PowerShell/PowerShell/issues/13344
      # !! The workaround is to delegate to Windows PowerShell.
      iet powershell.exe -noprofile -c $sb -args $exePath
    }
    else {
      # Windows PowerShell: execute the script block directly.
      & $sb $exePath
    }
  
  } 

  $exePath # Return the executable's path.

}
