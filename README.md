[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/Native.svg)](https://powershellgallery.com/packages/Native) [![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/mklement0/Native/blob/master/LICENSE.md)

# `Native` - a PowerShell Module for Native-Shell and External-Executable Calls

`Native` is a **cross-edition, cross-platform PowerShell module** for PowerShell **version 3 and above**.

To **install** it for the current user, run `Install-Module Native -Scope CurrentUser` - see [Installation](#Installation) for details.

## Overview

* [`ins` (`Invoke-NativeShell`)](#ins-invoke-nativeshell) presents a **unified interface to the platform-native shell**, allowing you to pass a command line either as as an argument - a single string - or via the pipeline
  * e.g., `ins 'ver & whoami'` on Windows, `ins 'ls / | cat -n'` on Unix.

* [`ie` (short for: **I**nvoke (external) **E**xecutable)](#ie-short-for-invoke-external-executable) allows you to **pass arguments to external programs robustly**, to compensate for PowerShell's broken behavior as of v7.0.
  * e.g., `'a"b' | ie findstr 'a"b'` on Windows, `'a"b' | ie grep 'a"b'` on Unix.

* [`dbea` (`Debug-ExecutableArguments`)](#dbea-debug-executablearguments) is a **diagnostic command** for understanding and **troubleshooting how PowerShell passes arguments to external executables**.
  * e.g., `dbea -- one '' '{ "foo": "bar" }'` vs. - with implicit use of `ie` - `dbea -UseIe -- one '' '{ "foo": "bar" }'`

### Getting Help

All commands come with command-line help; examples, based on `ins`:

* `ins -?` shows brief, syntax-focused help.
* `help ins -Examples` shows examples.
* `help ins -Parameter UseSh` shows help for parameter `-UseSh`.
* `help ins -Full` shows comprehensive help that includes individual parameter descriptions and notes.

### Known Limitations

* With `ins` (`Invoke-NativeShell`) and `ie`, for technical reasons, you must **check only `$LASTEXITCODE`** for being nonzero in order to determine if the native shell signaled failure; do not use `$?`, whose value always ends up `$true`. Unfortunately, this means that you cannot meaningfully use these commands with `&&` and `||`, the [pipeline-chain operators](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_Pipeline_Chain_Operators); however, if _aborting_ your script in case of a nonzero exit code is desired, use the `-e` (`-ErrorOnFailure`) switch with `ins` or use the `iee` wrapper function for `ie`.
Once the ability for user code to _set_ `$?` [gets implemented](https://github.com/PowerShell/PowerShell/issues/10917#issuecomment-550550490), this problem could be fixed.

* **Passing `--`** to any _PowerShell_ command (which this module's commands invariably are) signals to PowerShell's parameter binder that all subsequent arguments are to be treated as positional ones.
  * Given that this (first) `--` is invariably _removed_ in the process, you need to pass it _again_ if the intent is to pass `--` _as an actual argument_ to the native shell / external executable.
  * While the behavior of the first `--` is helpful in the case of `ins` and `dbea`, because you can use it to disambiguate pass-through arguments from these commands' _own_ parameters, it may be unexpected in the case of `ie`, _all_ of whose arguments
  by definition are to be passed through.
  * Therefore, **use the following invocation patterns** (`...` representing pass-through arguments, possibly including `--`):
    * `dbea [<own-parameters>] -- ...`
    * `ins [<own-parameters>] '<command line>' -- ...` (`--` only needed if there are pass-through arguments)
    * `ie -- ...` (`--` only needed if `--` is among the arguments)

* For technical reasons you must ***quote* arguments that have the following form**:
  * A bareword (unquoted argument) that contains _commas_ - e.g. `a,b`; use `'a,b'` instead (or `"a,$b"` if string interpolation is needed).
  * Arguments of the form `-foo:bar` and `-foo.bar`; use `'-foo:bar'` and `'-foo.bar'` instead.
  * For details, refer to the `NOTES` section in the output from `Get-Help -Full ie`.

* **Limitations of the escaping of embedded (verbatim) `"` on Windows**, which apply to both `ie` and `ins`, because the latter uses the former behind the scenes:
  * In _PowerShell [Core]_, `\"` is used to escape `"` by default, because it is the safest choice.
    * An exception is made for the high-profile `msiexec.exe` and `msdeploy.exe` CLIs, which support `""`-escaping only.
    * Should there be other CLIs that also support `""`-escaping only, direct invocation and use of `--%`, the [stop-parsing symbol operator](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_Parsing) is required to pass arguments with embedded `"` chars. to them.
  * In _Windows PowerShell_, `""` is used by default, to work around legacy bugs.
    * An exception is made for the following CLIs, which are known to accept `\"`-escaping only: PowerShell's own CLIs (`pwsh` and `powershell`), `ruby`, `perl`, and `Rscript`.
    * CLIs that use the [`CommandLineToArgvW`](https://docs.microsoft.com/en-us/windows/win32/api/processenv/nf-processenv-getcommandlinew) Windows API function rather than the C/C++ runtime to parse their command lines do _not_ support `""`-escaping. Direct invocation and use of `--%` is required to pass arguments with embedded `"` chars. to them.

* Because of the accommodation for `msiexec`-style CLIs, arguments starting with a space-less word followed by`=` (e.g., `a=b`) are passed to batch files with that word and the `=` _unquoted_, which means that if those batch files perform argument-parsing themselves (rather than passing arguments _through_ with `%*`), they see _two_ arguments (e.g. `a` and `b`). Use direct invocation with `--%` to work around this problem, if necessary.

* Note: Calling `cmd.exe` directly with a command line passed as a _single argument_ (which is the only _robust_ way) to either `cmd /c` or `cmd /k` - e.g., `ie cmd /c 'dir "C:\Program Files"'` - is supported,
  but you don't actually need `ie` / `iee` for that, because PowerShell's lack of escaping of embedded double quotes is in this case canceled out by `cmd.exe` not expecting such escaping.
  However, as a courtesy, `ie` / `iee` makes a _multi_-argument command line more robust by transforming it into a single-argument one behind the scenes, so that something like  
  `ie cmd.exe /c "c:\program files\powershell\7\pwsh" -noprofile -c "'hi   there'"` works too, not just the single-argument form  
  `ie cmd.exe /c '"c:\program files\powershell\7\pwsh" -noprofile -c "''hi   there''"'`


## Command Descriptions

### `ins` (`Invoke-NativeShell`)

Presents a unified interface to the platform-native shell (`cmd.exe` on Windows, `/bin/bash` on Unix), allowing you to pass a command line either as as an argument - a single string - or via the pipeline:

* Examples:
  * Unix: `ins 'ls / | cat -n'` or `'ls / | cat -n' | ins`
  * Windows: `ins 'ver & whoami'` or `'ver & whoami' | ins`

* Add `-e` (`-ErrorOnFailure`) if you want `ins` to throw a script-terminating error if the native shell reports a nonzero exit code (if `$LASTEXITCODE` is nonzero).

* You can also pipe *data* to `ins`, in which case the command line must be passed as an argument
  * Examples:
    * Unix: `'foo', 'bar' | ins 'grep bar'`
    * Windows: `'foo', 'bar' | ins 'findstr "bar"'`

* You can also treat the native command line like an improvised _script_ (batch file) to which you can pass arguments; if you pipe the script, you must use `-` as the first positional argument to signal that the script is being received via the pipeline (stdin):
  * Examples:
    * Unix: `ins 'echo "[$1] [$2]"' one two` or `'echo "[$1] [$2]"' | ins - one two`
    * Windows: `ins 'echo [%1] [%2]' one two` or `'echo "[%1] [%2]"' | ins - one two`

* Note:
  * Because you're passing a command (line) written for a _different shell_, which has different syntax rules, it must be passed _as a whole_, as a single string. To avoid quoting issues and to facilitate passing multi-line commands with line continuations, you can use a _here-string_ - see below. You can use _expandable_ (here-)strings in order to embed _PowerShell_ variable and expression values in the command line; in that case, escape `$` characters you want to pass through to the native shell as `` `$ ``.

  * On Unix-like platforms, `/bin/bash` rather than `/bin/sh` is used as the native shell, given Bash's ubiquity. Use `-sh` (`-UseSh`) to use `/bin/sh` instead.

  * On Windows, a temporary _batch file_ rather than a direct `cmd.exe /c` call is used behind the scenes, (not just) for technical reasons. This means that batch-file syntax must be used, which notably means that loop variables must use `%%`, not just `%`, and that you may escape `%` as `%%` - arguably, this is for the better anyway. The only caveat is that aborting a long-running command with <kbd>Ctrl-C</kbd> will present the infamous `Terminate batch file (y/n)?` prompt; simple repeat <kbd>Ctrl-C</kbd> to complete the termination.

  * `--` can be used to disambiguate pass-through arguments from `ins` own parameters; if you need to disambgurate or pass `--` as a pass-through argument, place `--` before the list of pass-through arguments (`ins <ins-parameters> '<command-line>' -- ...`)

  * For technical reasons, you must check only `$LASTEXITCODE` for being nonzero in order to determine if the native shell signaled failure; do not use `$?`, which always ends up `$true`. Unfortunately, this means that you cannot meaningfully use this function with `&&` and `||`, the [pipeline-chain operators](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_Pipeline_Chain_Operators); however, if _aborting_ your script in case of a nonzero exit code is desired, use the `-e` (`-ErrorOnFailure`) switch.

### `ie` (short for: **I**nvoke (external) **E**xecutable)

Robustly passes arguments through to external executables, with proper support for arguments with embedded `"` (double quotes) and for empty string arguments:

* Examples (without the use of `ie`, these commands wouldn't work as expected as of PowerShell 7.0):
  * Unix: `'a"b' | ie grep 'a"b'`
  * Windows: `'a"b' | ie findstr 'a"b'`

* Note:
  * Unlike `ins`, `ie` expects you to use _PowerShell_ syntax and pass arguments _individually_, as you normally would in direct invocation; in other words: simply place `ie` as the command name before how you would normally invoke the external executable (if the normal invocation would synctactically require `&`, use `ie` _instead_ of `&`.)

  * There should be no need for such a function, but it is currently required because PowerShell's built-in argument passing is still broken as of PowerShell 7.0, [as summarized in GitHub issue #1995](https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606); should the problem be fixed in a future version, this function will detect the fix and will no longer apply its workarounds.

  * For technical reasons:
    * The first occurrence of `--` as a parameter is invariably removed by PowerShell; if your arguments include `--`, use the syntax `ie -- ...`
    * You must check only `$LASTEXITCODE` for being nonzero in order to determine if the executable signaled failure; do not use `$?`, which always ends up equal to `$true`. Unfortunately, this means that you cannot meaningfully use this function with `&&` and `||`, the [pipeline-chain operators](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_Pipeline_Chain_Operators); however, if _aborting_ your script in case of a nonzero exit code is desired, you can use the `iee` wrapper function: see below.

  * `ie` should be fully robust on Unix-like platforms, but on Windows the fundamental nature of argument passing to a process via a single string that encodes all arguments prevents a fully robust solution. However, `ie` tries hard to make the vast majority of calls work, by automatically handling special quoting needs for batch files and, in Powershell versions 5.1 and above, for executables such as `msiexec.exe` / `msdeploy.exe` and `cmdkey.exe` (run `Get-Help ie -Full` for details); by default it adheres to the [Microsoft C/C++ quoting conventions for process command lines](https://docs.microsoft.com/en-us/cpp/cpp/main-function-command-line-args?view=vs-2019#parsing-c-command-line-arguments), although in Windows PowerShell `""` rather than `\"` is used for escaping embedded `"` characters, for technical reasons. If `ie` doesn't work in a given call, use direct invocation with `--%`, the [stop-parsing symbol](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_Parsing) to control quoting explicitly, or call via `ins` (given that `cmd.exe` ultimately uses the quoting as specified).

* Use the closely related **`iee`** function (the extra "e" standing for "error") if you want a script-terminating error to be thrown if the external executable reports a nonzero exit code (if `$LASTEXITCODE` is nonzero); e.g., the following command would throw an error:
  * `iee whoami -nosuchoptions`

### `dbea` (`Debug-ExecutableArguments`)

A diagnostic command for understanding and troubleshooting how PowerShell passes arguments to external executables, similar to the venerable [`echoArgs.exe` utility](https://chocolatey.org/packages/echoargs).

* Pass arguments as you would to an external executable to see how they would be received by it and, on Windows only, what the entire command line that PowerShell constructed behind the scenes looks like (this doesn't apply on Unix, where executables don't receive a single command line containing all arguments, but - more reliably - an array of individual arguments).  
  * To prevent pass-through arguments from being mistaken for the command's own parameters, place `--` before the list of pass-through arguments, as shown in the examples.
  * Use `-ie` (`-UseIe`) in order to see how invocation via `ie` corrects the problems that plague direct invocation as of PowerShell 7.0.  
  * Use `-UseBatchFile` on Windows to use an argument-printing batch file instead of the .NET helper executable, to see how batch files receive arguments; `-UseWrapperBatchFile` uses an _intermediate_ batch file that passes the arguments through to the .NET helper executable, to see how batch files acting as CLI entry points affect the argument passing.

* Examples:
  * `dbea -- '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b' 'a"b'`
    * On Windows, you'll see the following output - note how the arguments were _not_ passed as intended:

          7 argument(s) received (enclosed in <...> for delineation):

            <a&b>
            <3 of snow Nat>
            <King>
            <Cole c:\temp>
            <1\ a>
            <">
            <b ab>

          Command line (helper executable omitted):

            a&b 3" of snow "Nat "King" Cole" "c:\temp 1\\" "a \" b" a"b

  * `dbea -ie -- '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b' 'a"b'`

    * Thanks to use of `ie`, you'll see the following output, with the arguments passed correctly:

          6 argument(s) received (enclosed in <...> for delineation):

            <>
            <a&b>
            <3" of snow>
            <Nat "King" Cole>
            <c:\temp 1\>
            <a \" b>
            <a"b>

          Command line (helper executable omitted):

            "" a&b "3\" of snow" "Nat \"King\" Cole" "c:\temp 1\\" "a \\\" b" a\"b

---

## Using Here-Strings with `ins` to Handle Complex Quoting and Line Continuations

The following Unix examples show the use of a verbatim here-string and an expandable here-string to pass a command line with complex quoting and line continuation to `ins`; the expandable variant allows you to embed PowerShell variable and expression values into the command line:

```powershell
# Verbatim here-string:
@'
printf '%s\n' \
       "{ \"foo\": 1 }" |
  grep foo
'@ | ins


# Expandable here-string:
# Embed a PowerShell variable value.
# NOTE: You must escape $ characters that the native shell rather than PowerShell
#       should interpret as `$
$propName = 'foo'
@"
pattern='foo'        # Define a native shell variable
printf '%s\n' \
       "{ \"$propName\": 1 }" |
  grep "`$pattern"  # Note the ` before $
"@ | ins
```

## Setting up a `PSReadline` Keyboard Shortcut for Scaffolding an `ins` Call with a Here-String.

If you place the following call in your `$PROFILE` file, you'll be able to use <kbd>Alt-V</kbd> to scaffold a call to `ins` with a verbatim here-string into which the current clipboard text is pasted.
<kbd>Enter</kbd> submits the call.

This is convenient for quick execution of command lines that were written for the platform-native shell, such as found in documentation or on [Stack Overflow](https://stackoverflow.com), without having to worry about adapting the syntax to PowerShell's.

```powershell
# Scaffolds an ins (Invoke-NativeShell) call with a verbatim here-string
# and pastes the text on the clipboard into the here-string.
Set-PSReadLineKeyHandler 'alt+v' -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@'`n`n'@ | ins ")
  foreach ($i in 1..10) { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardChar() }
  # Comment the following statement out if you don't want to paste from the clipboard.
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert((Get-Clipboard))
}
```

# Installation

## Installation from the PowerShell Gallery (PowerShell 5+)

**Prerequisite**: The `PowerShellGet` module must be installed (verify with `Get-Command Install-Module`).  
`PowerShellGet` comes with PowerShell version 5 or higher; it is possible to manually install it on versions 3 and 4 - see [the docs](https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget).

* Current-user-only installation:

```powershell
# Installation for the current user only.
PS> Install-Module Native -Scope CurrentUser
```

* All-users installation (requires elevation / `sudo`):

```powershell
# Installation for ALL users.
# IMPORTANT: Requires an ELEVATED session:
#   On Windows:
#     Right-click on the Windows PowerShell icon and select "Run as Administrator".
#   On Linux and macOS:
#     Run `sudo pwsh` from an existing terminal.
ELEV-PS> Install-Module Native -Scope AllUsers
```

See also: [this repo's page in the PowerShell Gallery](https://www.powershellgallery.com/packages/Native).

## Manual Installation (PowerShell 3 and 4)

Download this repository as a ZIP archive, extract it, and place the _contents_ of the `Native-master` subfolder into a folder named `Native` in one of the directories listed in the `$env:PSModulePath` variable; e.g., to install the module in the context of the current user, choose the following parent folders:

* **Windows**:
  * Windows PowerShell: `$HOME\Documents\WindowsPowerShell\Modules`
  * PowerShell Core: `$HOME\Documents\PowerShell\Modules`
* **macOs, Linux** (PowerShell Core): 
  * `$HOME/.local/share/powershell/Modules`

As long as you've cloned into one of the directories listed in the `$env:PSModulePath` variable - copying to some of which requires elevation / `sudo` - and as long your `$PSModuleAutoLoadingPreference` is either has no value (the default) or is set to `All`, calling `ins` or `ie` should import the module on demand.

To explicitly import the module, run `Import-Module Native`.

**Example**: Install as a current-user-only module (the code may be re-run later to install updated versions):

```powershell
& {
  $ErrorActionPreference = 'Stop'

  # Enable TLS v1.2, so that Invoke-WebRequest can download from GitHub.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  # Switch to the base directory of the current user's modules.
  Set-Location $(
    if ($env:OS -eq 'Windows_NT') { 
      "$HOME\Documents\{0}\Modules" -f ('WindowsPowerShell', 'PowerShell')[[bool]$IsCoreClr]
    } else {
      "$HOME/.local/share/powershell/Modules"
    }
  )

  # Download the ZIP archive.
  Invoke-WebRequest -OutFile Native.zip https://github.com/mklement0/Native/archive/master.zip

  # Extract the archive, which creates a Native subfolder that itself contains
  # a Native-master subfolder.
  Remove-Item -ea Ignore ./Native/* -Recurse -Force
  Add-Type -Assembly System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/Native.zip", "$PWD/Native")

  # Move the contents of the Native-master subfolder directly into ./Native
  # and clean up.
  Move-Item -Force ./Native/Native-master/* ./Native
  Remove-Item -Force ./Native/Native-master, Native.zip
}
```

Run `ins -?` to verify that installation succeeded and that the module is loaded on demand:
you should see brief CLI help text.

# License

See [LICENSE.md](./LICENSE.md).

# Changelog

See [CHANGELOG.md](./CHANGELOG.md).
