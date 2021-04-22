### 
# IMPORTANT: KEEP THIS MODULE PSv3-COMPATIBLE.
# Notably:
#   * do not use .ForEach() / .Where()
#   * do not use ::new()
#   * do not use Get-ItemPropertyValue
#   * do not use New-TemporaryFile
### 

Set-StrictMode -Version 1

# For older WinPS versions: Set OS/edition flags (which in PSCore are automatically defined).
# Note: Unlike in the Pester test files, $script: isn't strictly needed here, but silences 
#       the PSSA warning re assigning to automatic variables.
if (-not (Test-Path Variable:IsWindows)) { $script:IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $script:IsCoreCLR = $false }

# Test if a workaround for PowerShell's broken argument passing to external
# programs as described in
#   https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606
# is still required.
# NOTE:
#  We activate the PowerShell Core 7.2.0-preview.5+ experimental PSNativeCommandArgumentPassing feature, which is 
#  aimed at fixing #1995, and MAY be good enough to obviate our workarounds, but NOT YET AS OF PowerShell Core 7.2.0-preview.5,
#  because it LACKS VITAL ACCOMMODATIONS FOR CLIS ON WINDOWS - see https://github.com/PowerShell/PowerShell/issues/15143
#  We test
$PSNativeCommandArgumentPassing = 'Standard'
$script:needQuotingWorkaround = if ($IsWindows) {
  # The `choice` command is a trick to print an argument as-is; choice.exe expects \"-escaping.
  (choice.exe /d Y /t 0 /m 'Nat "King" Cole') -notmatch '"' -or
  $( # The \" test passed, but we must also test for batch-file ("") and msiexec-style accommodations (partial quoting of `foo="bar none"` arguments), in case a fix in PowerShell itself fails to incorporate these.
    $tmpBatchFile = [IO.Path]::GetTempFileName(); [IO.File]::Delete($tmpBatchFile); $tmpBatchFile += '.cmd'
    '@echo [%*]' | Set-Content -LiteralPath $tmpBatchFile
    (& $tmpBatchFile 'Andre "The Hawk" Dawson' 'foo=bar none') -ne '["Andre ""The Hawk"" Dawson" foo="bar none"]'
    [IO.File]::Delete($tmpBatchFile)
  )
}
else {
  # NOTE: On Unix, even the currently-lacking experimental PSNativeCommandArgumentPassing feature is a suffixient fix
  #       that obviates our workaround.
  (printf %s '"ab"') -ne '"ab"'
}

if ($script:needQuotingWorkaround) {
  # We've determined that we (still) need our workarounds - on Windows even with PSNativeCommandArgumentPassing as of PowerShell Core 7.2.0-preview.5.
  # Therefore, we deactivate the feature now, as our workarounds rely on the old, broken behavior.
  $PSNativeCommandArgumentPassing = 'Legacy'
}

#region -- EXPORTED members (must be referenced in the *.psd1 file too)

# -- Define the ALIASES to EXPORT (must be exported in the *.psd1 file too).

Set-Alias ins Invoke-NativeShell
Set-Alias dbea Debug-ExecutableArguments

# SEE THE BOTTOM OF THIS #region FOR AN Export-ModuleMember CALL REQUIRED
# FOR PSv3/4 COMPATIBILITY.

# Note: 'ie'  and 'iee' are *directly* used as the *function* names,
#       deliberately forgoing verbose names, for the reasons explained
#       in the comment-based help for 'ie'.

# --

function Invoke-NativeShell {
  <#
.SYNOPSIS
Executes a native shell command line. Aliased to: ins

.DESCRIPTION
Executes a command line or ad-hoc script using the platform-native shell,
optionally with pass-through arguments.

If no argument and no pipeline input is given, an interactive shell is entered.
Otherwise, pass a *single string* comprising one more commands for the native
shell to execute; e.g.:

  ins 'whoami && echo hi'

The native shell's exit code will be reflected in $LASTEXITCODE; use only 
$LASTEXITCODE to infer success vs. failure, not $?, which always ends up 
$true for technical reasons.
Unfortunately, this means that you cannot meaningfully combine this command
with && and ||, the pipeline-chain operators.
However, if you want to automatically abort a script (throw a script-terminating
error) in case of a nonzero exit code, you can use -e (-ErrorOnFailure).

For command lines with tricky quoting, use here-strings; e.g., on Unix:

  ins @'
    printf '%s\n' "3\" of rain."
  '@

Use an interpolating (here-)string to incorporate PowerShell values; use `$
for $ characters to pass through to the native shell; e.g., on Unix:

  ins @"
    printf 'PS version: %s\n' "$($PSVersionTable.PSVersion)"
  "@

Pipeline input is supported in two fundamental modes:

* The pipeline input is the *command line* to execute (`<commands> | ins`):

  * In this case, no -CommandLine argument must be passed, or, if pass-through
    arguments are specified, it must be '-' to explicitly signal that the
    command line is coming from the pipeline (stdin)
    (`<commands> | ins - passThruArg1 ...`).
    Alternatively, use parameeter -Args explicitly with an array of values to
    unambiguously identify them as pass-through arguments
    (`<commands> | ins -Args passThruArg1, ...`).

* The pipeline input is *data* to pass *to* the command line to execute
  (`<data> | ins <commands>`):

.PARAMETER CommandLine
The command line or ad-hoc script to pass to the native shell for execution.

Ad-hoc script means that the string you pass can act as a batch file / shell
script that is capable of receiving any pass-through arguments passed via
-ArgumentList (-Args) the usual way (e.g., %1 as the first argument on Windows,
and $1 on Unix).

You may omit this parameter and pass the command line via the pipeline instead.
If you use the pipeline this way on and you additionally want to specify
pass-through arguments positionally, you can pass '-' as the -CommandLine
argument to signal that the code is specified via the pipeline; alternatively,
use the -ArgumentList (-Args) parameter explicitly, in which case you must
specify the arguments as an *array*.

IMPORTANT:
  On Windows, the command line isn't executed directly by cmd.exe, 
  but via a temporary *batch file*. This means that batch-file syntax rather
  than command-prompt syntax is in effect, which notably means that you need %% 
  rather  than just % before `for` loop variables (e.g. %%i) and that you may
  escape verbatim % characters as %%

.PARAMETER ArgumentList
Any addtional arguments to pass through to the ad-hoc script passed to
-CommandLine or supplied via the pipeline.

IMPORTANT:

* These arguments bind to the standard batch-file / shell-script 
  parameters starting with %1 / $1. See the NOTES section for more information.

* If you pass the pass-through arguments individually, positionally, 
  precede them with an extra '--' argument to avoid name conflicts with
  this function's own parameters (which includes the supported common
  parameters). This is also necessary if you want to pass -- through to the
  native shell.

* If the command line is supplied via the pipeline, you must either pass '-'
  as -CommandLine or use -ArgumentList / -Args explicitly and specify the 
  pass-through arguments *as an array*.

* For technical reasons you must *quote* arguments that contain commas, 
  look like `-foo:bar` or `-foo.bar`, e.g. `'foo,bar'` instead of `foo,bar`.

.PARAMETER UseSh
Supported on Unix-like platforms only (ignored on Windows); aliased to -sh:

Uses /bin/sh rather than /bin/bash for execution.

Note that /bin/sh, which is the official system shell on Unix-like platforms, 
can be expected to support POSIX-compliant features only, which notably
precludes certain Bash features, such as [[ ... ]] conditionals, process
substitutions, <(...), and Bash-specific variables.

Conversely, if your command line does work with -UseSh, it can be assumed 
to work in any of the major POSIX-compatible shells: bash, dash, ksh, and zsh.

.PARAMETER ErrorOnFailure
Triggers a script-terminating error if the native shell indicates overall
failure of the command line's execution via a nonzero exit code; aliased to
-e.

The error record generated shows an *approximation* of the original command
line in its TargetObject property; that is, it shows a concatenation of the
verbatim expanded arguments without consistently reflecting necessary quoting 
or escaping.

IMPORTANT: This switch acts independently of PowerShell's error handling, 
which as of v7.1 does not act on nonzero exit codes reported by external
executables.
There is a pending RFC to change that:
  https://github.com/PowerShell/PowerShell-RFC/pull/88
Once it gets implemented, this commmand will
be subject to this new integration in the absence of -ErrorOnFailure (-e).

.PARAMETER InputObject
This is an auxiliary parameter required for technical reasons only.
Do not use it directly.

.EXAMPLE
ins 'ver & date /t & echo %CD%'

Windows example: Calls cmd.exe with the given command line, which ouputs 
cmd.exe version information and prints the current date and working directory.

.EXAMPLE
'ver & date /t & echo %CD%' | ins

Windows example: Equivalent command using pipeline input to pass the command
line.

.EXAMPLE
'foo', 'bar' | ins 'findstr bar & ver'

Windows example: Passes data to the command line via the pipeline (stdin).

.EXAMPLE
$msg = 'hi'; ins "echo $msg"

Uses string interpolation to incorporate a PowerShell variable value into
the native command line.

.EXAMPLE
ins -e 'whoami -nosuchoption'

Uses -e (-ErrorOnFailure) to request throwing an error if the native shell
reports a nonzero exit code, as is the case here.

.EXAMPLE
ins 'ls / | cat -n'

Unix example: Calls Bash with the given command line, which lists the files 
and directories in the root directory and numbers the output lines.

.EXAMPLE
ins 'ls "$1" | cat -n; echo "$2"' $HOME 'Hi there.'

Unix example: uses a pass-through argument to pass a PowerShell variable value
to the Bash command line.

.EXAMPLE
'ls "$1" | cat -n; echo "$2"' | ins -UseSh - $HOME 'Hi there.'

Unix example: Equivalent of the previous example with the command line passed 
via the pipeline, except that /bin/sh is used for execution.
Note that since the command line is provided via the pipeline and there are
pass-through arguments present, '-' must be passed as the -CommandLine argument.

.EXAMPLE
'one', 'two', 'three' | ins 'grep three | cat -n'

Unix example: Sends data through the pipeline to pass to the native command
line as stdin input.

.EXAMPLE
ins @'
  printf '%s\n' "6'1\" tall"
'@

Unix example: Uses a (verbatim) here-string to pass a command line with
complex quoting to Bash.

.NOTES

* By definition, calls to this function are *platform-specific*.
  To perform platform-agnostic calls to a single external executable, use the
  `ie` function that comes with this module.

* On Unix-like platforms, /bin/bash is used by default, due to its ubiquity.
  If you want to use the official system default shell, /bin/sh, instead, use 
  -UseSh. Without -UseSh, /bin/sh is also used as a fallback in the unlikely
  event that /bin/bash is not present.

* When /bin/bash and /bin/sh accept a command line as a CLI argument, it is via 
  the -c option, with subsequent positional arguments getting passed 
  *to the command line* being invoked; curiously, however, the first such 
  argument sets the *invocation name* that the command line sees as special 
  parameter $0; it is only the *second* argument that becomes $1, the first 
  true script parameter (argument).
  Since this is somewhat counterintuitive and since setting $0 in this scenaro 
  is rarely, if ever, needed, this function leaves $0 at its default (the path
  of the executing shell) and passes any pass-through arguments (specified via
  -ArgumentList / -Args or positionally) starting with parameter $1.

* On Windows, <systemRoot>\System32\cmd.exe is used, where <systemroot> is
  the Windows directory path as stored in the 'SystemRoot' registry value at
  'HKEY_LOCAL_MACHINE:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; the 
  following options, which explicitly request cmd.exe's default behavior, are 
  used to ensure a predictable execution environment: /d /e:on /v:off

* That $? ends up $true even if the native shell reported a nonzero exit code 
  (reflected in $LASTEXITCODE) cannot be avoided as of v7.1; however there are 
  plans to eventually make $? settable from user code; see
  https://github.com/PowerShell/PowerShell/issues/10917#issuecomment-550550490

#>

  [CmdletBinding(PositionalBinding = $false)]
  param(
    [Parameter(Position = 1)]
    [string] $CommandLine
    ,
    [Parameter(Position = 2, ValueFromRemainingArguments = $true)]
    [Alias('Args')]
    [string[]] $ArgumentList
    ,
    [Alias('sh')]
    [switch] $UseSh
    ,
    [Alias('e')]
    [switch] $ErrorOnFailure
    ,
    [Parameter(ValueFromPipeline = $true)] # Dummy parameter to ensure that pipeline input is accepted, even though we use $input to process it.
    $InputObject
  )

  # Note: If -UseSh is passed on Windows, we *ignore* it rather than throwing an error.
  #       This makes it easier to create cross-platform commands in that only the command-line
  #       string must be provided via a variable (with platform-appropriate content).
  
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
    # Note: By default, due to its ubiquity, we use /bin/bash, unless -UseSh was passed or /bin/bash doesn't exist (unlikely).
    if ($UseSh -or -not (Test-Path -PathType Leaf '/bin/bash')) {
      # The de-facto standard location for the default system shell on Unix-like platforms.
      '/bin/sh'
    }
    else {
      '/bin/bash'
    }
  }

  # We invoke the native shell via 'ie' by default, or, if erroring out on
  # nonzero exit codes is requsted, via 'iee'
  $invokingFunction = ('ie', 'iee')[$ErrorOnFailure.IsPresent]

  $havePipelineInput = $MyInvocation.ExpectingInput
  $pipelineInputIsCommandLine = $havePipelineInput -and (-not $CommandLine -or $CommandLine -eq '-')

  if (-not $havePipelineInput -and -not $CommandLine) { 
    # If neither a command line nor pipeline input is given, enter an interactive
    # session of the target shell.
  
    Write-Verbose "Entering interactive $nativeShellExePath session..."
  
    & $invokingFunction $nativeShellExePath
  
  }
  else {
    # A command line / ad-hoc script must be passed to the native shell.

    # NOTE: For reasons that differ by platform, we translate a code-via-stdin (pipeline) (`... | ins`)
    #       invocation to a code-by-argument / code-by-temporary-batch-file invocation.
    if ($pipelineInputIsCommandLine) {

      $pipelineInputIsCommandLine = $havePipelineInput = $false
      $CommandLine = @($Input) -join "`n" # Collect all pipeline input and join the (stringified) objects with newlines.

      # RATIONALE:
      # Windows:
      #   * cmd.exe doesn't properly support piping *commands* to it:
      #     The "logo" is always printed, and lines are executed one after, with
      #     the prompt string printed after each, and by default each command is 
      #     also echoed before execution (only this aspect can be controlled, with /q)
      #   * Similarly, passing multi-line strings to cmd /c isn't supported:
      #     Only the *first* line is processed, the rest are *ignored*.
      #   Since we're using a temporary *batch file* for invocation anyway, 
      #   we can offer the same code-via-pipeline experience as with bash/sh:
      #   Essentially, a multi-line ad-hoc batch file may be passed.
      #
      # Unix:
      #   * While bash/sh are perfectable cable of receiving ad-hoc scripts via
      #     stdin, we still translate the invocation into a `-c <string>`-based
      #     one, so as to support commands that ask for *interactive input*.
      #     If we used the pipeline/stdin, the *code itself*, by virtue of 
      #     being received via stdin, would be used to automatically respond to
      #     interactive prompts.

    }

    # As a courtesy, we make sure that if arguments are passed, the target
    # commmand (ad-hoc script) actually contains references to those arguments,
    # and warn otherwise, as that likely means that the user accidentally
    # used `ins foo bar` when they meant to use `ins 'foo bar'`
    if ($ArgumentList) {
      # Note: These regexes aren't fool-proof (may yield false positives that result in no warning when there should be one), but should work well enough.
      #       We could in theory limit the $\d / %\d matching to the number of arguments passed (e.g., not allow $3 if only 2 args. are passed), but that doesn't seem worth it.
      $regex = if ($IsWindows) { '%\*|%\d|%~[^\d]*\d' } else { '\$\{?\*\}?|\$\{?@\}?|\$\{?\d\}?' }
      if ($CommandLine -notmatch $regex) {
        Write-Warning "You are passing arguments to the -CommandLine argument, but the latter doesn't reference them. Did you mean to make them part of the -CommandLine string? E.g. ``ins 'echo hi'`` rather than ``ins echo hi``"
      }
    }

    if ($IsWindows) {
      # On Windows, we use a temporary batch file to avoid re-quoting problems 
      # that would arise if the command line were passed to cmd /c as an *argument*.
      # This invariably means that batch-file rather than command-line syntax is 
      # expected, which, however, is arguably preferable anyway.

      Write-Verbose "Passing commands via a temporary batch file to $nativeShellExePath..."

      $tmpBatchFile = [IO.Path]::GetTempFileName(); [IO.File]::Delete($tmpBatchFile); $tmpBatchFile += '.cmd'

      # Write the command line to the temp. batch file.
      Set-Content -Encoding Oem -LiteralPath $tmpBatchFile -Value "@echo off`n$CommandLine"

      # To be safe, use an empty array rather than $null for array splatting below.
      if ($null -eq $ArgumentList) { $ArgumentList = @() }

      # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
      #            is present. If no input is present, PowerShell *still
      #            redirects* the target executable's stdin and simply makes it
      #            *empty*. This causes command lines with *interactive* prompts
      #            to malfunction.
      #            Also: We cannot use an intermediate script block invoked
      #                  with & here in order to avoid duplicating the actual
      #                  command: the pipeline input is then NOT passed through
      #                  (you'd have to use $input inside the script block too, which amounts to a catch-22).
      if ($havePipelineInput) { 
        # Note: For predictability, we use explicit switches in order to get what should be the default
        #       behavior of cmd.exe on a pristine system:
        #       /d == no auto-run, /e:on == enable command extensions; /v:off == disable delayed variable expansion
        # IMPORTANT: Changes to this call must be replicated in the `else` branch below.
        $input | & $invokingFunction $nativeShellExePath /d /e:on /v:off /c "$tmpBatchFile $ArgumentList & exit" # !! The '& exit' is for robust exit-code reporting - see https://stackoverflow.com/a/67009271/45375
      } 
      else { 
        # IMPORTANT: Changes to this call must be replicated in the `if` branch above.
        & $invokingFunction $nativeShellExePath /d /e:on /v:off /c "$tmpBatchFile $ArgumentList & exit" # !! See explanation for the `& exit ` part above.
      }

      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile

    }
    else {
      # Unix

      Write-Verbose "Passing commands as an argument to $nativeShellExePath..."

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
  
      # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
      #            is present. If no input is present, PowerShell *still
      #            redirects* the target executable's stdin and simply makes it
      #            *empty*. This causes command lines with *interactive* prompts
      #            to malfunction.
      #            Also: We cannot use an intermediate script block invoked
      #                  with & here in order to avoid duplicating the actual
      #                  command: the pipeline input is then NOT passed through.
      #                  (you'd have to use $input inside the script block too).
      if ($havePipelineInput) { 
        # IMPORTANT: Changes to this call must be replicated in the `else` branch.
        $input | & $invokingFunction $nativeShellExePath -c $CommandLine $passThruArgs
      } 
      else { 
        & $invokingFunction $nativeShellExePath -c $CommandLine $passThruArgs
      }

    }

  }

  # Witout -e, $? *always* ends up as $true for the caller, irrespective of
  # the $LASTEXITCODE value, unfortunately, which cannot be helpd as of v7.1. 
  # This means you cannot use this function meaningfully with && and ||.
  # There is no workaround as of PowerShell Core 7.1.0-preview.5, but there
  # are plans to make $? settable by user code: see
  # https://github.com/PowerShell/PowerShell/issues/10917#issuecomment-550550490

}


function ie {
  <#
.SYNOPSIS
Invokes an external executable with robust argument passing.

.DESCRIPTION
Invokes an external executable with arguments passed through properly, even if
they contain embedded double quotes or they're the empty string, to compensate
for PowerShell's broken argument passing up to at least v7.1
'ie' stands for 'Invoke (External) Executable'

Use this function by simply prefixing a call to an external executable with
'ie' as the command (if invocation via call operator '&' would
normally be necessary, use 'ie' *instead* of it). E.g., on Unix:

  ie printf '"%s" ' print these arguments quoted
  
IMPORTANT:

* To check if the executable signaled failure, see if $LASTEXITCODE is nonzero.
Do not use $?, which always ends up as $true.
Unfortunately, this means that you cannot meaningfully use this function with
&& and ||, the pipeline-chain operators.
However, if you want to automatically abort a script (throw a 
script-terminating error) if failure is signaled, you can call the related 
'iee' wrapper function.

* Use of --%, the stop-parsing symbol, with this function is NOT supported, 
but it is never necessary on Unix platforms, and should generally not be 
necessary on Windows, because this function automatically handles special
quoting needs of batch files and, in PowerShell v5.1 and above, of
high-profile CLIs such as msiexec.exe, msdeploy.exe, and cmdkey.exe - 
see the NOTES section. In the rare event that you do need --%, use it with
direct invocation, as usual, or invoke via ins (Invoke-NativeShell).

* -- as an argument is invariably removed by PowerShell on invocation, for
  technical reasons. If you need to pass -- through to the executable, use
  the form `ie -- ...`, i.e. use an extra -- before all arguments.

* For technical reasons you must *quote* arguments that contain commas,
  look like `-foo:bar` or `-foo.bar`, e.g. `'foo,bar'` instead of `foo,bar`.

Since the invocation solely relies on PowerShell's own argument-mode
syntax and since, as in direct invocation, no other shell is involved,
this function is suitable for use in *cross-platform*  code, unlike the
platform-specific calls to Invoke-NativeShell / ins.

This function is intentionally implemented as a *simple* function, and
therefore doesn't support any common parameters (just like direct invocation
doesn't).

.EXAMPLE
ie echoArgs.exe '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'  'a"b'

Calls the echoArgs.exe executable on Windows, which echoes the individual 
arguments it receives in diagnostic form as follows, showing that the arguments
were passed as intended:

    Arg 0 is <>
    Arg 1 is <a&b>
    Arg 2 is <3" of snow>
    Arg 3 is <Nat "King" Cole>
    Arg 4 is <c:\temp 1\>
    Arg 5 is <a \" b>
    Arg 6 is <a"b>

    Command line:
    "C:\ProgramData\chocolatey\lib\echoargs\tools\EchoArgs.exe" "" a&b "3\" of snow" "Nat \"King\" Cole" "c:\temp 1\\" "a \\\" b" a\"b

Note: echoArgs.exe is installable via Chocolatey using the following commmand
from an elevated session:

    choco install echoargs -y 

However, the dbea (Debug-NativeExecutable) command that comes with the same 
module as this function provides the same functionality, and the equivalent
invocation would be:

dbea -ie -- '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'  'a"b'

.NOTES

Background information on PowerShell's broken argument handling:
https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606

That $? ends up $true even if the executable reported a nonzero exit code 
(reflected in $LASTEXITCODE) cannot be avoided as of v7.1; however there are 
plans to eventually make $? settable from user code; see
https://github.com/PowerShell/PowerShell/issues/10917#issuecomment-550550490

That you must *quote* arguments that contain commas, look like `-foo:bar` or 
`-foo.bar`:

 * is unavoidable in the case of values with commas: PowerShell-native commands
  - which this module's commands are - receive such arguments differently
  than external executables, namely as *arrays*, and passing such arrays on to
  external executables invariably passes the array's elements as *individual
  argumetns*:
     * `a,b` and `a, b` both become array `'a', 'b'`, which, when passed to an
       external exeuctables passes two separate arguments `a` and `b`.

 * in the case of `-foo:bar` and `-foo.bar` it is arguably PowerShell bugs that
   cause such arguments to be broken into *two* - see these issues:
   https://github.com/PowerShell/PowerShell/issues/6360
   https://github.com/PowerShell/PowerShell/issues/6291

These transformations happen before this module's commands receive their
arguments, without their knowledge, so they cannot be compensated for.

External executable in this context means any executable that PowerShell must
invoke via a child process, which encompasses not just binary executables,
but also batch files, WSH scripts, and other shells' or scripting languages' 
scripts.

The only reason for this function's existence is that up to at least
PowerShell 7.1, arguments passed to external programs are not passed
correctly if they are either the empty string or have embedded double quotes.
Should the underlying problem ever be fixed in PowerShell itself, this
function will no longer apply its workarounds and will effectively act like 
'&', the call operator. See the NOTES section for a link to more information.

This function is intentionally designed to be a minimalist stopgap that
should be unobtrusive and simple to use. It is therefore implemented as 
a *simple* function and does *not* support common parameters (just like
you can't use common parameters with direct invocation).

The specifics of accommodating batch-file calls are as follows:

* Embedded double quotes, if any, are escaped as "" in all arguments.
* Any argument that contains *no spaces* but contains either double quotes
  or cmd.exe metacharacters such as "&" is enclosed in double quotes
  (whereas PowerShell by default only encloses arguments *with spaces* in
  double quotes); e.g., a verbatim argument seen by PowerShell as `a&b` is
  placed as `"a&b"` on the command line passed to a batch file; specifically,
  the following characters trigger this behavior: & | < > ^ , ; "
* CAVEAT: An argument that starts with a space-less word followed by `=`, 
  e.g. `a=b`, is always passed with that word and the `=` *unquoted*, as part
  of the accommodations for msiexec-style CLIs (see below). While this doesn't
  affect argument pass-through with `%*`, intra-batch-file parsing of arguments
  results in such a token being broken into *two* arguments, `a` and `b`.

NOTE: Calling cmd.exe directly with a command line passed as a single argument
      - e.g. `ie cmd /c 'dir "C:\Program Files"'` - is supported,
      but you don't actually need this function for that, because PowerShell's 
      lack of escaping of embedded double quotes is in this case canceled out 
      by cmd.exe not expecting such escaping. Additionally, as a courtesy, this
      function transforms a multi-argument command line into a single-argument
      one for increased robustness.

The specifics of accommodating WSH calls are as follows:

WSH (Windows Script Host, whose CLIs are cscript.exe and wscript.exe) is also 
implicitly called when executing files with one of the following extensions, 
which are present in $env:PATHEXT, comprising both VBScript and JScript files
and their variations, as well as WSH wrapper files:

  Extensions: .vbs .vbe .js .jse .wsf .wsh

In PowerShell Core, which defaults to \"-escaping of embedded ", ""-escaping
is used when a WSH script is implicitly or explicitly called, which, however,
only *mitigates* the fundamental problem that WSH supports neither \" or ""-
escaping: With ""-escaping, whil the embedded " are still mistakenly
*stripped*, at least the argument boundaries are preserved.

The specifics of accommodating high-profile CLIs such as msiexec.exe /
msdeploy.exe and cmdkey.exe are as follows:

On Windows, any invocation that contains at least one argument of the following
forms triggers the behavior described below; `<word>` can be composed of 
letters, digits, and underscores:
  * <word>=<value>
  * /<word>:<value>
  * -<word>:<value>
More formally, an argument that matches regex '^([/-]\w+[=:]|\w+=)(.+)$' 
triggers the behavior.

If such an argument is present:

* In PowerShell v5.1 and above, if the <value> part has spaces, only *it* is 
  enclosed in double quotes, *not* the argument *as a whole* (which is what
  PowerShell - justifiably - does by default); e.g., a verbatim argument
  seen by PowerShell as `foo=bar none` is placed as `foo="bar none"` on the
  process' command line (rather than as `"foo=bar none"`).
  The aforementioned high-profile CLIs require this very specific form of
  quoting, unfortunately.
  Unfortunately, this accommodation doesn't work in PowerShell v3 and v4.

* Additionally, embedded double quotes, if any, are escaped as "":
  * in PowerShell *Core*: for `msiexec` abd `msideploy` *only*
  * in *Windows PowerShell*: for *all* executables, with only a few well-known 
    exceptions (see below).

If the accommodation is needed but cannot be applied - in Windows PowerShell 
v3 and v4 and in PowerShell Core for CLIs other than `msiexec` abd `msideploy`
- you can call via Invoke-NativeShell or cmd /c "..."

In Windows PowerShell, this function uses "" by default used for "-escaping,
whereas in PowerShell Core it defaults to the more widely supported \"-escaping.

Note: The use of ""-escaping by default in Windows PowerShell, employed to
work around a legacy bug, is a compromise that favors avoiding broken behavior
with embedded quotes over supporting CLIs that do not support ""-escaping. 

Most CLIs on Windows support *both* "" and \"-escaping, but notably those that
use the CommandLineToArgvW  WinAPI function to parse their command line support
\" only. The assumption is that *most* CLIs use the C/C++ runtime's argv parsing
instead.

However, there are high-profile exceptions: 
  ruby, perl, Rscript, and PowerShell's own CLIs, pwsh and powershell.
When these are called, this function uses \"-escaping in Windows PowerShell
(too), becaues the use of embedded " chars. would otherwise fail fundamentally.

To avoid the legacy bug when \"-escaping must be used in Windows PowerShell - 
which affects arguments that have a non-initial embedded " not preceded by an 
unprotected space char, such as `print("hi there")` or `3" of snow` - a
trailing, unprotected space is added to the argument, based on the assumption
that a *whole command line* for the target CLI is being passed (as a single 
string), in which case trailing spaces should not affect functionality.

However, this workaround cannot be safely applied to arguments passed to
*scripts* implicitly executed by these target CLIs, such as `.rb` files for
Ruby. Again, Invoke-NativeShell or direct invocation with use of --% offer
workarounds; e.g.:
  .\foo.rb --% "3\" of snow"

#>

  # IMPORTANT: 
  #  We deliberately declare NO parameters, because any parameter could interfere
  #  with the pass-through arguments and then - unexpectedly and cumbersomely - require -- before these arguments.
  #  The problem is that even a single-character prefix of a declared parameter name would be bound to it.
  #  E.g., a -WhatIf parameter would be bound by -w
  # param()

  # Split into executable name/path and arguments.
  # Note: We can't assume that $argsForExe will be a flat array - see below.
  $exe, $argsForExe = $args

  if (-not $exe) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [System.Management.Automation.ParameterBindingException] "Missing mandatory parameter: Please specify the external executable to invoke.",
          'MissingMandatoryParameter',
          'InvalidArgument',
          $null
        ))
    )
  }

  # Resolve the targeted executable to its full path.
  # Note: 
  #  * Even if we wanted to support calls to PowerShell-native commands too, 
  #    we cannot, given that this simple function is based on the array of positional arguments, $args. 
  #    While @args has built-in magic for passing even *named* arguments through,
  #    we need to split $args into executable name and remaining arguments here, and the magic doesn't work with custom arrays.
  #  *  We explicitly look for (aliases of) external executables only, bypassing other 
  #     command forms that would normally have higher precedence, namely
  #     namely functions and cmdlets.
  #     !! Using -CommandType implies -All, so we must limit the results to the *first* command found.
  #     !! Due to this function being defined in a *module*, only aliases defined in the *global* scope are recognized.
  $app = Get-Command -ErrorAction Ignore -CommandType Alias, Application $exe | Select-Object -First 1
  if ($app -and $app.CommandType -eq 'Alias') { $app = $app.ResolvedCommand }
  if (-not $app -or $app.CommandType -ne 'Application') {
    # No command $exe that is (an alias of) an external executable (.CommandType 'Application') found.
    $msg = if (-not $app) {
      "No external executable '$exe' found."
    }
    else {
      "Alias '$exe' resolves to '$($app.Name)', which is not an external executable."
    }
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [ArgumentException] $msg,
          'ApplicationNotFoundException',
          'InvalidArgument',
          $exe
        ))
    ) 
  }  
  # Use the full path for invocation, to avoid having to re-resolve the executable as specified to the underlying full path.
  #  Note: Regrettably, Get-Command also reports *documents* as commands of type 'Application' - see https://github.com/PowerShell/PowerShell/issues/12625
  #        While we could do our own subsequent analysis to see if a true executable was specified, that doesn't seem worth the trouble.
  #        It's usually pointless to invoke a document directly *with additional arguments*, which are usually ignored.
  $exe = $app.Path

  # Flatten the array of arguments, because we also want to support invocations such as `ie $someArray foo bar`, 
  # i.e. a mix of array-splatting and indiv. args.
  # NOTE:
  #  * We coerce to [string[]] up front, which applies PowerShell's usual culture-invariant string formatting for values such as `1.2`
  #  * Since we're by definition calling *external programs*, everything is passed as a string anyway; note that [Array]::FindIndex requires a strongly typed index, for instance.
  $orgExeArgs = $argsForExe # Also save the array of original arguments with their original types, in case the workaround is no longer needed or a script block-based PowerShell CLI invocation is being performed.
  [string[]] $argsForExe = foreach ($potentialArrayArg in $argsForExe) { foreach ($arg in $potentialArrayArg) { $arg } }

  # Determine the base name and filename extension of the target executable, as we need to vary 
  # the quoting behavior based on it:
  $null = $app.Path -match '[/\\]?(?<exe>[^/\\]+?)(?<ext>\.[^.]+)?$'
  $exeBaseName, $ext = $Matches['exe'], $Matches['ext']

  # Infer various executable characteristics:
  $isBatchFile = $IsWindows -and $ext -in '.cmd', '.bat'
  $isCmdExe = $IsWindows -and -not $isBatchFile -and ($exeBaseName -eq 'cmd' -and $ext -eq '.exe') # cmd.exe, the legacy Windows shell
  $isWsh = $IsWindows -and -not ($isBatchFile -or $isCmdExe) -and ($ext -in '.vbs', '.vbe', '.js', '.jse', '.wsh', '.wsf' -or ($exeBaseName -in 'cscript', 'wscript' -and $ext -eq '.exe')) # WSH is being called, either explicitly or 
  # See if a PowerShell CLI is being invoked, so we can detect whether a *script block* is among the arguments,
  # which causes PowerShell to transform the invocation into a Base64-encoded one using the -encodedCommand CLI parameter.
  $isPsCli = $exeBaseName -in 'powershell', 'pwsh' -and $ext -in $null, '.exe'
  # See if the exe is one of the high-profile CLIs that require *partial* double-quoting of arguments such as `FOO="bar none"`.
  # Also, these exes require ""-escaping (except cmdkey.exe, which doesn't support embedded " at all).
  $isMsiExecLikeExe = $exeBaseName -in 'msiexec', 'msdeploy', 'cmdkey' -and $ext -eq '.exe'
  # Determine whether the target executable *only* supports \" for "-escaping.
  #  * On Unix, that applies to *all* executables (if invoked via a pseudo-command line assigned to ProcessStartInfo.Arguments, as PowerShell currently does).
  #  * On Windows, where most CLIs support *both* \" and "", supporting \" *only* is limited to a few WELL-KNOWN CLIs,
  #    which are BLACKLISTED HERE (of course, there could be more).
  #    THIS BLACKLIST ONLY APPLIES TO *WINDOWS POWERSHELL*, where we default to ""-escaping to work around legacy bugs.
  #    (In PS Core we default to \"=escaping anyway.)
  #    !! BE SURE TO REFLECT CHANGES HERE IN THE .NOTES SECTION ABOVE.
  $supportsBackslashDQuoteOnly = -not $IsWindows -or (($exeBaseName -in 'perl', 'ruby', 'Rscript', 'powershell', 'pwsh' -and $ext -eq '.exe') -or ($ext -in '.pl', '.rb', '.r')) # Note: we needn't worry about '.ps1', because they are exeuted in-process.

  # The regex that determines for direct cmd.exe and batch-file calls, both of which are transformed into a `cmd /c "<command-line>"` call,
  # which arguments require double-quoting, which obviously includes arguments with *spaces*, but also space-*less* arguments that contain
  # cmd.exe metacharacters. 
  # NOTE: "=" - even though it also serves as an argument separator, alongside space, "," and ";" - is NOT included, so as to give precedence to the msiexec-style partial double-quoting requirements.
  # !! CHANGES TO THIS REGEX MUST BE REPLICATED IN THE .NOTES SECTION of the comment-based help above.
  $reMustDQuoteForCmd = '[&|<>^,; "]'
  # The regex that matches all argument-interior embedded double quotes (to be applied after having enclosed an argument in outer double quotes).
  $reInteriorDQuotes = '(?<=.)"(?!$)'

  # The regex that identifies msiexec-style arguments such as `FOO="bar none"` or `/foo:"bar none"` / `-foo:"bar none"` that require *partial* double-quoting, namely
  # of the *value* part (to the right of ":" / "=", if necessary.
  # The regex splits into property/parameter name and value via capture groups, but itself doesn't try to determine if actual double-quoting of the value part is necessary.
  # !! CHANGES TO THIS REGEX MUST BE REPLICATED IN THE .NOTES SECTION of the comment-based help above.
  $rePartialDQuotingCandidate = '^([/-]\w+[=:]|\w+=)(.+)$'

  # == Construct the array of escaped arguments, if necessary.
  # Note: We cannot use .ForEach('GetType'), because we must remain PSv3-compatible.
  [array] $escapedArgs = 
  if ($null -eq $argsForExe -and -not $isBatchFile) {
    # To be safe: If there are no arguments to pass, use an *empty array* for splatting so as
    #             to be sure that *no* arguments are passed. We don't want to rely on passing $null
    #             getting the same no-arguments treatment in all PS versions.
    # Exception:  For robustness, *batch files* must becalled as cmd /c "<batch-file> ... & exit /b" - see below.
    @()
  }
  elseif (-not $script:needQuotingWorkaround -or ($isPsCli -and $orgExeArgs.ForEach('GetType') -contains [scriptblock])) {
    # Use the arguments as-is if (a) the quoting workaround is no longer needed or (b) the engine itself will aply Base64-encoding behind the scenes
    # using the -encodedCommand CLI parameter.
    # Note: As of PowerShell Core 7.1.0-preview.5, the engine unexpectedly applies Base64-encoding in the presence of a [scriptblock] argument alone,
    #       irrespective of what executable is being invoked: see https://github.com/PowerShell/PowerShell/issues/4973
    #       In effect we're masking the bug by exhibiting more sensible behavior if the executable is NOT a PowerShell CLI (stringified script block, which may still not be the intent),
    #       in the hopes that the bug will get fixed and that direct execution will then exhibit the same behavior.
    $orgExeArgs
  
  }
  elseif ($isCmdExe) {
    # -- Special handling for cmd.exe
    # Find the index of either the /c or the /k switch, whichever comes first:
    # Note: The [string[]] cast ensures a strongly typed array, which is necessary for method overload resolution to find a suitable generic overload, 
    #       Since we've type-constrained $argsForExe to [string[]] above, this isn't strictly necessary here, however.
    $cmdLineArgOptionNdx = [Array]::FindIndex([string[]] $argsForExe, [Predicate[string]] { $args[0] -in '/c', '/k' })
    if ($cmdLineArgOptionNdx -eq -1) {
      # By definition, there's no command to pass to cmd.exe for execution, as cmd.exe ignores any unrecognized tokens unless 
      # they follow /c or /k - irrespective of whether they look like options (e.g. `/uga`) or operands (e.g., `foo`).
      # We're either dealing with a valid invocation that uses only options to control the interactive sessions (e.g. `cmd /v`)
      # or a broken invocation.
      # Either way, there's nothing to escape, so pass all arguments through without escaping.
      $argsForExe
    }
    else {
      # The assumption is that anything preceding /c or /k is only other switches, which also need
      # no escaping (anything else would be a broken cmd.exe invocation anyway.)
      $argsForExe[0..$cmdLineArgOptionNdx]
      # The remaining arguments by definition make up the command line to pass to cmd.exe.
      # Note that the only way to *robustly* pass such a command line is *as a single argument* enclosed in `"..."` overall.
      # Passing a single argument requires NO escaping, because PowerShell's lack of escaping of embedded double-quotes is 
      # in this case canceled out by cmd.exe not expecting such escaping(!)
      # In short: 
      #   * There is no need to use `ie` for passing a *single-argument* command-line to cmd /c or cmd /k. 
      #   * However, at least we don't want to break if `ie` is used, and as a courtesy we make passing *multi-argument* command lines more robust.
      if ($cmdLineArgOptionNdx -le $argsForExe.Count - 2) {
        if ($cmdLineArgOptionNdx -eq $argsForExe.Count - 2) {
          # *single-argument* command line, pass it through - rely on PowerShell's broken argument-passing.
          $argsForExe[-1]
        }
        else {
          # *multi*-argument command line.
          # As a courtesy, we transform these multiple arugments into a *single*-argument command line, by 
          # space-joining them, which requires double-quoting them individually on demand, as for batch files.
          # PowerShell's broken argument-passing will blindly enclose this in `"..."` overall - which is what cmd.exe expects.
          # CAVEAT: Embedded " in individual arguments are ""-escaped to be batch file-friendly, 
          #         but this which can break CLIs that only understand \" - such as WinPS (but fortunately no longer PS Core).
          $argsForExe[($cmdLineArgOptionNdx + 1)..($argsForExe.Count - 1)].ForEach( { ($_, "`"$_`"")[$_ -match $reMustDQuoteForCmd] -replace $reInteriorDQuotes, '""' }) -join ' '
        }
      }
    }
  }
  elseif ($isBatchFile) {
    # -- SPECIAL HANDLING FOR BATCH FILES IN ORDER TO *SUPPORT RELIABLE EXIT-CODE REPORTING*:
    #    See our SO question and answer at https://stackoverflow.com/a/67009271/45375
    #    We call via `cmd /c "<batch-file> ... & exit "`, using the same escaping as for direct `cmd /c` / `cmd /k` calls above.
    #       #  Hypothetical caveat: Since we must use ""-escaping when calling batch files: In the case of batch files acting as CLI entry points (such as `az.cmd` for Azure), 
    #       #                       this escaping could still break if the ultimate target executable only supports \"
    #       #                       A least officially provided CLI entry points hopefully account for that (i.e., they hopefully only chose batch-file entry points if the code ultimately processing the arguments recognizes "" as an escaped ")
    '/c', (((, $exe + $argsForExe).ForEach( {
            if ($_ -match $rePartialDQuotingCandidate) {
              # support for partial double-quoting of msiexec-style arguments such as `foo="bar none"` - see above.
              $prefix, $arg = $Matches[1], $Matches[2]
            }
            else {
              $prefix, $arg = '', $_
            }
            $prefix + (($arg, "`"$arg`"")[$arg -match $reMustDQuoteForCmd] -replace $reInteriorDQuotes, '""')
          }) + '& exit') -join ' ')
    $exe = "$env:SystemRoot\System32\cmd.exe"

  }
  else {
    # Escape all arguments properly to pass them through as seen verbatim by PowerShell.

    # Decide whether to escape embedded double quotes as \" or as "", based on the target executable.
    $useDoubledDQuotes = if ($IsCoreCLR) {
      # PSCore:
      # * On Unix: we always use \" (which ProcessStartInfo.Arguments recognizes when it parses the pseudo command line into the array of arguments).
      # * On Windows: We only use "" if we have to: for batch files and direct cmd.exe calls, for misexec-like executables, and for WSH calls (VBScript, JScript)
      #               The assumption is that all executables support \" (typically in *addition* to the Windows-only "").
      #               Batch-file caveat: In the case of batch files acting as CLI entry points (such as `az.cmd` for Azure), the "" quoting
      #                                  could still break if the ultimate target executable only supports \"
      #               WSH limitation: WSH supports neither "" nor \" as an escaped, embedded ", but using "" is *less* broken than \", 
      #                               because - even though the embedded " are still *stripped* - at least the argument boundaries are preseved
      #                               (because somethinglike `"Nat ""King"" Cole"` is parsed as a compound token composed of `"Nat "`, `"King"`, and `"Cole"`),
      #                               whereas \" would not only not preserve argument boundaries but also retain the \ chars. 
      $isBatchFile -or $isCmdExe -or $isMsiExecLikeExe -or $isWsh # Note: The $isBatchFile case is now handled in a separate block above.
    }
    else {
      # WinPS:
      # So as to eliminate edge cases where \" doesn't work due to PowerShell's re-quoting (see below) as much as possible, 
      # we REVERSE the logic and *use "" by default*, except for known exceptions: Ruby, Perl, Rscript and the PowerShell CLIs (both editions) themselves, which all support \" only.
      # All other executables are assumed to support "".
      # !! THIS IS NOT NECESSARILY TRUE, HOWEVER, because executables that use the CommandLineToArgvW WinAPI function to parse their arguments do NOT support ""
      # !! However, we still go with "" by default, under the assumption that CLI executables are more likely to use the C/C++ runtime's argv parsing, which DOES support "".
      # !! This is invariably a COMPROMISE.
      -not $supportsBackslashDQuoteOnly
    }
    $escapedDQuote = ('\"', '""')[$useDoubledDQuotes]
    
    foreach ($arg in $argsForExe) {

      if ('' -eq $arg) { '""'; continue } # Empty arguments must be passed as `'""'`(!), otherwise they are omitted.
      # Note: $null values - which we want to ignore - are seemingly automatically eliminated during splatting, which we use below.

      # Determine argument characteristics.
      $hasDQuotes = $arg.Contains('"')
      $hasSpaces = $arg.Contains(' ')
      # Determine if *explicit* double-quoting must be used, as a *workaround*:
      #  * On Unix:
      #     * Never: letting PowerShell automatically put the enclosing "..." around arguments *with spaces* on the pseudo-commad line assigned to ProcessStartInfo.Arguments is sufficient.
      #  * On Windows:
      #     * If ""-escaping is used and a space-less argument contains "
      #     * If a space-less argument is passed to a batch file and the argument contains cmd.exe metacharacters such as "&"
      #       !! "=" ALSO belongs on the list of metacharacters, because in batch-file parsing - but not in pass-through with %* -
      #       !! it separates arguments, just like "," and ";". However, enclosing tokens such as `FOO=bar` in double quotes
      #       !! CONFLICTS with the MSI-style exceptions for NOT double-quoting the `FOO=` part of such arguments.
      #       !! We're faced with the choice between passing `FOO=bar`, which makes misexec-style exes happy vs. `"FOO=bar"`, which
      #       !! makes batch-file argument-parsing happy. We give precdence to the FORMER; fortunately, argument *pass-through* with %* isn't affected.
      #     * Potentially (determined below), if *partial* double-quoting is needed (e.g., `FOO="bar none"`)
      $mustManuallyDQuote = $IsWindows -and -not $hasSpaces -and (($useDoubledDQuotes -and $hasDQuotes) -or ($isBatchFile -and $arg -match '[&|<>^,;]')) # !! See comment re "=" above; also note: The $isBatchFile case is now handled in a separate block above.
      # Determine if the argument must *end up* with double-quoting on the process command line on Windows, 
      # whether applied as a workaround explicitly by us, or whether triggered by PowerShell due to embedded spaces.
      $mustEndUpDQuoted = $hasSpaces -or $mustManuallyDQuote

      # Windows only:
      # See if *partial double-quoting for msiexec-style CLIs* must be applied (e.g., `FOO="bar none"` or `/foo:"bar none"` / `-foo:"bar none"`)
      # (By default, PowerShell - justifiably - passes such arguments as `"<propertyOrOptionName>=value with spaces"`, i.e. enclosed in double quotes *as a whole*,  which breaks such CLIs.)
      # Note: 
      #  * ":" only triggers this quoting if the argument starts with "/"  or "-", so that we don't accidentally turn `c:\program files` into `c:\"program files"`.
      #  * We do NOT restrict this quoting to when $isMsiExecLikeExe is $true, so as to cover potential other CLIs that need this quoting.
      #    However, given that in *PS Core* we use ""-escaping *only* when $isMsiExecLikeExe is $true, i.e. if specific executables are detected, any other CLIs
      #    must understand \"-escaping if embedded " are present for the call to succeed (in *Windows PowerShell*, we *default* to ""-escaping to work around legacy bugs).
      #  * The partial double-quoting should be benign if it isn't actually needed, because conventional CLIs parse both `FOO="bar none"` and `"FOO=bar none"` as verbatim `FOO=bar none`.
      #  * CAVEAT: In WinPS v3 and v4 only, *a partially quoted value that contains spaces*, such as `foo="bar none"`,
      #            causes the engine to still enclose the entire argument in "...", which cannot be helped.
      #            Only a *space-less* value that needs double-quoting is handled correctly (which may never occur in practice).
      #            Calls to msiexec / msdeploy and cmdkey with values with spaces will therefore break and require --% in v3 and v4 - 
      #            we could blindly still try the partial quoting, as the call will break either way, but it's better to highlight PowerShell's built-in behavior.
      $mustPartiallyDQuote = $IsWindows -and $mustEndUpDQuoted -and $arg -match $rePartialDQuotingCandidate -and ($PSVersionTable.PSVersion.Major -ge 5 -or -not $hasSpaces)
      if ($mustPartiallyDQuote) {
        # Split into - by definition pass-as-unquoted - prefix and the needs-double-quoting suffix.
        $prefix, $arg = $Matches[1], $Matches[2]
        $mustManuallyDQuote = $true
      }
      else {
        $prefix = ''
      }
  
      if ($hasDQuotes -and -not $IsCoreCLR -and $supportsBackslashDQuoteOnly -and $ext -eq '.exe' -and $arg -match '^[^ ]+\".*? .*\"[^ ]*$') {        
        # !! Hack to work around a WinPS bug:
        # !! If the \"-escaping must be used in arguments with spaces, WinPS doesn't recognize the need to "..."-enclose the argument
        # !! if those spaces are inside the \"...\" sequence *and what precedes the opening \" contains no spaces*.
        # !! The workaround of explicitly embedded enclosing `"..."` does NOT work in this case, due to the `\"-escaping - 
        # !! avoiding this bug is why we chose to default to ""-escaping in WinPS to begin with.
        # !! E.g, `print(\"hello there\")` (by contrast `print (\"hello there\")` is fine, due to the unprotected first space).
        # !!
        # !! Given that we therefore use \"-escaping only for "blacklisted" CLIs of which we know that they don't support ""-escaping, 
        # !! and of which we also know that they expect command lines of *theirs* passed as single strings
        # !! (ruby, perl, Rscript, pwsh, powershell; e.g., `Rscript -e 'print("hi there")'`),
        # !! we assume that *adding an extra, unprotected leading or trailing space* to avoid the bug is *benign*.
        # !! Note:
        # !!  If a *script* for one of these CLIs is called, we must *not* apply this hack, because the script arguments
        # !!  cannot be assumed to be *command lines* for the implied target CLI, so such invocations will *break*.
        # !!  However, it is less likely that arguments of the problematic form are passed - as data rather than code - to scripts.
        # Write-Debug "adding trailing space for \"-only CLI to work around WinPS bug: $arg"
        $arg += ' '  # Append trailing, unprotected space to force WinPS to double
      }
      
      # Escape any embedded " first and
      # *double \ instances before them*, because a verbatim `\"` sequence would otherwise be interpreted as an *escaped* "
      # Note: We must must do this even when using ""-escaping on Windows, because Windows CLIs that accept ""-escaping *also* accept \"-escaping - even in a single argument.
      $arg = $arg -replace '\\+(?=")', '$&$&' -replace '"', $escapedDQuote

      # If double-quoting must be used, trailing '\'s must be doubled.
      # so that `c:\program files` translates to `"c:\program files\\"` - without the doubling the trailing \" would be interpreted as an *escaped* "
      # * If we end up applying the double-quoting explicitly ourselves, we must always perform this escaping explicitly.
      # * Otherwise, if we rely on PowerShell to apply the double-quoting, this escaping happens *automatically* in *PS Core*, but must still be done *manually* in *WinPS*>
      if ($mustManuallyDQuote -or (-not $IsCoreCLR -and $mustEndUpDQuoted)) { $arg = $arg -replace '\\+$', '$&$&' }

      # Write-Debug "after escaping: $arg"
      
      # Apply explicit double-quoting, if necessay, and prepend the prefix, if partial quoting was applied.
      $arg = $prefix + $(if ($mustManuallyDQuote) { '"{0}"' -f $arg } else { $arg })

      # Write-Debug "final: $arg" # !! PowerShell could still end up putting extra "..." around it on final process command line on Windows.

      $arg # output the escaped argument.
      
    }
  }

  if ($DebugPreference -eq 'Continue') {
    # See the verbatim arguments about to be passed.
    , $exe + $escapedArgs | % { "«$_»" } | Write-Debug
  }

  # Finally, invoke the executable with the properly escaped arguments, if any, possibly with pipeline input.  
  # Note: We must use @escapedArgs rather than $escapedArgs, otherwise PowerShell won't apply
  #       Base64 encoding in the presence of a script-block argument when its CLI is called.
  #       Use of @ also results in --% getting removed, but we don't support it meaningfully anyway.
  if ($MyInvocation.ExpectingInput) {
    # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
    #            is present. If no input is present, PowerShell *still
    #            redirects* the target executable's stdin and simply makes it
    #            *empty*. This causes command lines with *interactive* prompts
    #            to malfunction.
    #            Also: We cannot use an intermediate script block invoked
    #                  with & here in order to avoid duplicating the actual
    #                  command: the pipeline input is then NOT passed through
    #                  (you'd have to use $input inside the script block too, which amounts to a catch-22).
    # IMPORTANT: Changes to this call must be replicated in the `else` branch.
    $input | & $exe @escapedArgs
  }
  else {
    & $exe @escapedArgs
  }

  # $? *always* ends up as $true for the caller, irrespective of
  # the $LASTEXITCODE value, unfortunately, which cannot be helpd as of v7.1. 
  # This means you cannot use this function meaningfully with && and ||.
  # There is no workaround as of PowerShell Core 7.1.0-preview.5, but there
  # are plans to make $? settable by user code: see
  # https://github.com/PowerShell/PowerShell/issues/10917#issuecomment-550550490

}

function iee {
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
iee curl.exe -u jdoe 'https://api.github.com/user/repos' -d '{ "name": "foo"}'

Invokes the external curl utility to create a new GitHub repo.
If doing so fails, as indicated by curl's process exit code being nonzero,
an script-terminating error is thrown.

.NOTES

Once the following RFC is implemented, you'll be able to use a preference
variable to control how nonzero exit codes reported by external programs are
handled:

https://github.com/PowerShell/PowerShell-RFC/pull/88

#>
  # IMPORTANT: See the comments inside `ie` for why we must NOT declare any parameters.

  if ($MyInvocation.ExpectingInput) {
    # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
    #            is present. If no input is present, PowerShell *still
    #            redirects* the target executable's stdin and simply makes it
    #            *empty*. This causes command lines with *interactive* prompts
    #            to malfunction.
    #            Also: We cannot use an intermediate script block invoked
    #                  with & here in order to avoid duplicating the actual
    #                  command: the pipeline input is then NOT passed through
    #                  (you'd have to use $input inside the script block too, which amounts to a catch-22).
    # IMPORTANT: Changes to this call must be replicated in the `else` branch.
    $input | ie @args
  }
  else {
    ie @args
  }

  if ($LASTEXITCODE) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [System.Management.Automation.ApplicationFailedException] "`"$($args[0])`" terminated with nonzero exit code $LASTEXITCODE.",
          'NativeCommandFailed',
          'OperationStopped',
          "$args"  # Report the full command, though note that this is just a space-separated list of the verbatim arguments, without quoting and escaping.
        ))
    )
  }

}

function Debug-ExecutableArguments {
  <#
.SYNOPSIS
Debugs external-executable argument passing. Aliased to: dbea

.DESCRIPTION
Acts like an external executable that prints the arguments passed to it in 
diagnostic form, similar to what the well-known third-party echoArgs.exe 
utility does on Windows.

IMPORTANT: 
 * To prevent confusion between this command's own parameters
   and pass-through arguments, precede the latter with --
   E.g.: dbea -- sed -i 's/a/b/' 'file 1.txt'

 * For technical reasons you must *quote* arguments that contain commas, 
   look like `-foo:bar` or `-foo.bar`, e.g. `'foo,bar'` instead of `foo,bar`.

On Windows, the whole command line is printed as well.
On Unix, there is no point in doing so, as processes there do not receive a
single command line that encodes all arguments, but an array of verbatim
strings.

The default output is formatted for easy readability by humans.
Using -Raw prints the argument values received as-is, undecorated.

This function is useful for diagnosing the problems with passing empty-string
arguments and arguments with embedded double quotes to external executables
that exist up to at least v7.0 and are detailed here:

https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606

You can avoid these problems altogether if you use the 'ie' function to call
external executables, whose use behind the scenes you can request with -ie 
(-UseIe).

Hidden helper executables / scripts, created on demand, are used to receive and
print the given arguments. By default, a helper binary is used on Windows, 
and an ad-hoc /bin/sh script on Unix.

On Windows, you can alternatively use -UseBatchFile to pass the arguments to
an argument-printing batch file instead, or -UseWrapperBatchFile to use an 
intermediate batch file to pass the arguments through to the helper binary.

.PARAMETER ArgumentList
The arguments to pass - either with -ArgumentList / -Args as an *array*,
or more conveniently, as *individual*, positional arguments.

That is, the following two invocations are equivalent:

  Debug-ExecutableArguments -Args one, two, three

and:

  Debug-ExecutableArguments -- one two three

Note: The '--' isn't strictly necessary in this example, but it reliably
      disambiguates pass-through arguments from this command's own parameters.
      E.g., without '--', an intended pass-through argument '-r' would bind
      to the -Raw switch. 

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

.PARAMETER UseWSH
On Windows, uses a VBScript file executed via WSH (cscript.exe) rather than 
the helper binary to print the arguments it receives in diagnostic form.

.PARAMETER Raw
Prints the arguments only, as-is, each on its own line. 
No delimiters are used and no other information is printed.

This makes the output suitable for programmatic processing, but only as long
none of the arguments span multiple lines.

.EXAMPLE
Debug-ExecutableArguments -- -u '' 'https://api.github.com/user/repos' -d '{ "name": "foo" }'

On Unix, you'll see the following output as of v7.0:

  4 argument(s) received (enclosed in «...» for delineation):

    «-u»
    «https://api.github.com/user/repos»
    «-d»
    «{ name: foo }»

Note the missing empty-string argument and the loss of the embedded " chars.

On Windows, you'll additionally see the following as of v7.0:

  Command line (without executable):
    -u https://api.github.com/user/repos -d "{ "name": "foo" }"

The command line shows that the empty-argument string was never passed, and
the lack of escaping the embedded " chars., when the argument was re-quoted
behind the scenes to use double quotes, resulted in their effective removal
(because the argument was intrepreted as a composite string composed of
double-quoted and unquoted parts).

.EXAMPLE
Debug-ExecutableArguments -UseIe -Raw -- -u '' 'https://api.github.com/user/repos' -d '{ "name": "foo" }'

Same arguments as in the previous example, but with the -UseIe (-ie) switch
added to compensate for the broken argument passing via the ie function, 
and the -Raw switch to print the arguments received verbatim, without decoration.

On both Windows and Unix you'll see the following output as of v7.0, which shows
that the arguments were now passed correctly (the empty line represents the 
empty-string argument):

  -u

  https://api.github.com/user/repos
  -d
  { "name": "foo" }

.NOTES

On Windows, a helper executable in the form of a .NET console appplication
is created on demand in the following location:

  $env:TEMP\f7fd420a-47e4-4216-bd57-c88696123608\dbea.exe

You can delete it anytime, but note that you'll pay a performance penalty for
its re-creation on the next invocation.

#>

  [CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'Default')]
  param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [Alias('Args')]
    $ArgumentList
    ,
    [Parameter(ParameterSetName = 'BatchFile', Mandatory)]
    [switch] $UseBatchFile
    ,
    [Parameter(ParameterSetName = 'WrapperBatchFile', Mandatory)]
    [switch] $UseWrapperBatchFile
    ,
    [Parameter(ParameterSetName = 'WSH', Mandatory)]
    [switch] $UseWSH
    ,
    [Alias('ie')]
    [switch] $UseIe
    ,
    [switch] $Raw
  )
  
  if (($UseBatchFile -or $UseWrapperBatchFile -or $UseWSH) -and -not $IsWindows) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [System.PlatformNotSupportedException] "The -UseBatchFile, -UseWrapperBatchFile, and -UseWSH parameters are only supported on Windows.", 
          'PlatformNotSupportedException', 
          'InvalidArgument', 
          $null
        ))
    )
  }

  # Communicate -Raw, i.e. the desire to print just the raw arguments received -
  # via an *environment variable* to the helper executable / scripts.
  if ($Raw) { $env:_dbea_raw = 1 }

  if ($IsWindows) {
    
    # Note: Unless explicitly requested to use a batch file only, we need a 
    #       binary helper executable to robustly replicate what external executables 
    #       will receive as arguments, so we create a .NET console application on demand, 
    #       using inline C# code.
    #       Note: This application will invariably recognize "" as an alternative to \"
    #             escaping, which most, but not all CLIs on Windows do.
    $helperBinary = if (-not $UseBatchFile) { get-WinHelperBinaryPath }

    if ($UseBatchFile -or $UseWrapperBatchFile) {
  
      $tmpBatchFile = [IO.Path]::GetTempFileName(); [IO.File]::Delete($tmpBatchFile); $tmpBatchFile += '.cmd'
    
      $content = if ($UseWrapperBatchFile) {
        # The wrapper batch file simply passes all args through to the helper binary.
        "@$helperBinary %*"
        Write-Verbose "Executing helper binary `"$helperBinary`" via temporary wrapper batch file `"$tmpBatchFile`""
      }
      else {
        # Create the argument-echoing batch file on demand.
        if ($Raw) {
          @'
@echo off
:for_arg

  if %1.==. goto :eof

  echo %1

  shift
goto for_arg
'@
        }
        else {
          @'
@echo off
setlocal

call :count_args %*
echo %ReturnValue% argument(s) received (enclosed in «...» for delineation):
echo.

:for_arg

  if %1.==. goto for_arg_done

  echo   «%1»

  shift
goto for_arg
:for_arg_done

echo.
echo Command line (without executable; the value of %%*):
echo.
echo.  %*
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
      }
      Set-Content -Encoding Oem -LiteralPath $tmpBatchFile -Value $content
    
      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because we want to support --%, the stop-parsing symbol.
      if ($UseIe) {
        ie $tmpBatchFile @ArgumentList
      }
      else {
        & $tmpBatchFile @ArgumentList
      }
    
      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile
    
    } # END of: if ($UseBatchFile -or $UseWrapperBatchFile)
    elseif ($UseWSH) {

      $tmpVbScriptFile = [IO.Path]::GetTempFileName(); [IO.File]::Delete($tmpVbScriptFile); $tmpVbScriptFile += '.vbs'

      # Create the argument-echoing VBScript file on demand.
      $content = if ($Raw) {
        @'
for each arg in WScript.Arguments
  WScript.Echo arg
next
'@
      }
      else {
        @'
WScript.Echo CStr(WScript.Arguments.Count) + " argument(s) received:" + vbLf

Dim i
i = 0
for each arg in WScript.Arguments
  i = i + 1
  WScript.Echo "  «" + arg + "»"
next

WScript.Echo
'@
      }

      # We must use ANSI encoding for the «» chars. to render properly.
      if ($IsCoreCLR) {
        [int] $ansiCp = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage ACP).ACP
        Set-Content -Encoding $ansiCp -LiteralPath $tmpVbScriptFile -Value $content
      }
      else {
        Set-Content -Encoding Default -LiteralPath $tmpVbScriptFile -Value $content
      }

      Write-Verbose "Executing argument-echoing VBScript file via WSH: $tmpVbScriptFile"

      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because we want to support --%, the stop-parsing symbol.
      #       Also, we use cscript.exe explicitly to ensure console output (default host may be wscript.exe)
      if ($UseIe) {
        ie cscript.exe $tmpVbScriptFile @ArgumentList
      }
      else {
        & cscript.exe $tmpVbScriptFile @ArgumentList
      }

      Remove-Item -ErrorAction Ignore -LiteralPath $tmpVbScriptFile
      
    }
    else {
      # Windows, no batch file or WSH
      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because (on Windows) we want to support --%, the stop-parsing symbol.
      Write-Verbose "Executing helper binary: $helperBinary"
      if ($UseIe) {
        ie $helperBinary @ArgumentList
      }
      else {
        & $helperBinary @ArgumentList
      }
    }


  } # END of: if ($IsWindows)
  else {
    # Unix

    Write-Verbose "Executing ad-hoc in-memory /bin/sh script."

    # No need for a binary executable - a shell script will do.
    # Note: For consistency, and since --% is technically (albeit mostly uselessly)
    #       supported on Unix too, we also use @ArgumentList rather than $ArgumentList on Unix.
    $script = @'
if [ -z "$_dbea_raw" ]; then
  printf '%s\n\n' "$# argument(s) passed (enclosed in «...» for delineation):"
fi

for a; do 
  if [ -z "$_dbea_raw" ]; then
    printf '  «%s»\n' "$a"
  else
    printf '%s\n' "$a"
  fi
done

if [ -z "$_dbea_raw" ]; then
  printf '%s\n'
fi
'@

    if ($UseIe) {
      # !! The use of `ie` necessitates an extra '--', because the first '--'
      # !! is invariably "eaten" by PowerShell's parameter binding.
      $script | ie /bin/sh -s -- -- @ArgumentList
    } 
    else {
      $script | /bin/sh -s -- @ArgumentList
    }

  }

  if ($Raw) { $env:_dbea_raw = $null }

}

# !! For PSv3 and PSv4, the aliases must be exported explicitly with 
# !! Export-ModuleMember - referencing them in the *.psd1 file is NOT enough.
# !! Since use of Export-ModuleMember overrides the implicit exports, the
# !! function must then also be specified.
# !! By doing this *here*, `-Function *` includes all functions defined
# !! *so far* in this file, which are the ones we want to export.
if ($PSVersionTable.PSVersion.Major -le 4) {
  Export-ModuleMember -Alias * -Function *
}

# -- endregion


#endregion -- EXPORTED members


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

    bool raw = "1" == Environment.GetEnvironmentVariable("_dbea_raw", EnvironmentVariableTarget.Process);

    if (! raw) 
    {
      Console.WriteLine("{0} argument(s) received (enclosed in «...» for delineation):\n", args.Length);
    }

    for (int i = 0; i < args.Length; ++i) {
      if (raw)
      {
        Console.WriteLine(args[i]);
      }
      else
      {
        Console.WriteLine("  «{0}»", args[i]);
      }
    }

    if (! raw)
    {
      // Get the full command line and strip the executable (which is either
      //  - when invoked by PowerShell: the full, double-quoted path.
      //  - when invoked via a batch file: the path is not necessarily quoted.
      string cmdLine = Environment.CommandLine;
      cmdLine = cmdLine.Substring(Regex.Match(cmdLine, "\".+?\"|[^\\s]+").Value.Length).TrimStart();
  
      Console.WriteLine("\nCommand line (without executable):\n\n  {0}\n", cmdLine);
    }

    return 0;
  }
}
'@
    }
    if ($IsCoreCLR) {
      # !! As of PowerShell Core 7.1.0-preview.5, -OutputType ConsoleApplication produces
      # !! broken executables in PowerShell *Core* - see https://github.com/PowerShell/PowerShell/issues/13344
      # !! The workaround is to delegate to Windows PowerShell.
      # Note: To simplify troubleshooting, we don't use `iee` here.
      & {
        $ErrorActionPreference = 'Continue'
        $out = powershell.exe -noprofile -c $sb -args $exePath 2>&1
      }
      if (0 -ne $LASTEXITCODE) {
        throw "FAILED TO CREATE HELPER EXECUTABLE '$exePath':`n$out"
      }
    }
    else {
      # Windows PowerShell: execute the script block directly.
      & $sb $exePath
    }
  
  } 

  $exePath # Return the executable's path.

}
