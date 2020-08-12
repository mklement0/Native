[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/Native.svg)](https://powershellgallery.com/packages/Native) [![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/mklement0/Native/blob/master/LICENSE.md)

# `Native` - a PowerShell Module for Native-Shell and External-Executable Calls

`Native` is a **cross-edition, cross-platform PowerShell module** for PowerShell **version 3 and above**.

To **install** for the current user, run `Install-Module Native -Scope CurrentUser` - see [Installation](#Installation) for details.

The module comes with the following commands:

* **`ins` (`Invoke-NativeShell`)** presents a unified interface to the platform-native shell, allowing you to pass a command line either as as an argument - a single string - or via the pipeline:
  * Examples:
    * Unix: `ins 'ls -d / | cat -n'` or `'ls -d / | cat -n' | ins`
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

* **`ie`** (short for: **I**nvoke (external) **E**xecutable) robustly passes arguments through to external executables, with proper support for arguments with embedded `"` (double quotes) and for empty-string arguments:

  * Examples (without the use of `ie`, these commands wouldn't work as expected, as of PowerShell 7.0):
    * Unix: `'a"b' | ie grep 'a"b'`
    * Windows: `'a"b' | ie findstr 'a"b'`

  * Note:
    * Unlike `ins`, `ie` expects you to use _PowerShell's_ syntax and pass the arguments _individually_, as you normally would in direct invocation; in other words: simply place `ie` as the command name before how you would normally invoke the external executable (if the normal invocation would synctactically require `&`, use `ie` _instead_ of `&`.)
    * There should be no need for such a function, but it is currently required because PowerShell's built-in 
  argument passing is still broken as of PowerShell 7.0, [as summarized in this GitHub issue](https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606); should the problem be fixed in a future version, this function will detect the fix and will no longer apply its workarounds.

  * Use the closely related **`iee`** function (the extra "e" standing for "error") if you want a script-terminating error to be thrown if the external executable reports a nonzero exit code (if `$LASTEXITCODE` is nonzero); e.g., the following command would throw an error:
    * `iee git clone http://example.org/no-git-repo-here`

* **`dbea` (`Debug-ExecutableArguments`)** is a diagnostic command for understanding and troubleshooting how PowerShell passes arguments to external executables, similar to the venerable [`echoArgs.exe` utility](https://chocolatey.org/packages/echoargs).

  * Pass arguments as you would to an external executable to see how they would be received by it and, on Windows only, what the entire command line that PowerShell constructed behind the scenes looks like (this doesn't apply on Unix, where executables don't receive a single command line containing all arguments, but - more sensibly - an array of individual arguments).  
  Use `-ie` (`-UseIe`) in order to see how invocation via `ie` corrects the problems that plague direct invocation as of PowerShell 7.0.

  * Examples:
    * `dbea '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'`
      * On Windows, you'll see the following output - note how the arguments were _not_ passed as intended:

            7 argument(s) received (enclosed in <...> for delineation):

              <a&b>
              <3 of snow Nat>
              <King>
              <Cole c:\temp>
              <1\ a>
              <">
              <b>

            Command line (helper executable omitted):

              a&b 3" of snow "Nat "King" Cole" "c:\temp 1\\" "a \" b"

    * `dbea -ie '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'`

      * Thanks to use of `ie`, you'll see the following output in PowerShell v6+, with the arguments passed correctly (note: in _Windows PowerShell_ you'll still see a problem, namely with `'3" of snow'`, which Windows PowerShell neglects to enclose in `"..."` behind the scenes, due to the non-initial `"` not being preceded by a space):

            6 argument(s) received (enclosed in <...> for delineation):

              <>
              <a&b>
              <3" of snow>
              <Nat "King" Cole>
              <c:\temp 1\>
              <a \" b>

            Command line (helper executable omitted):

              "" a&b "3\" of snow" "Nat \"King\" Cole" "c:\temp 1\\" "a \\\" b"

---

All commands come with **help**; examples, based on `ins`:

* `ins -?` shows brief, syntax-focused help.
* `help ins -Examples` shows examples.
* `help ins -Parameter UseSh` shows help for parameter `-UseSh`.
* `help ins -Full` shows comprehensive help that includes individual parameter descriptions.

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

If you place the following call in your `$PROFILE` file, you'll be able to use <kbd>Alt-v</kbd> to scaffold a call to `ins` with a verbatim here-string into which the current clipboard text is pasted.
<kbd>Enter</kbd> submits the call.

This is convenient for quick execution of command lines that were written for the platform-native shell, such as found in documentation or on stackoverflow.com, without having to worry about adapting the syntax to PowerShell's.

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

## Installation from the PowerShell Gallery

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

## Manual Installation

Clone this repository (as a subfolder) into one of the directories listed in the `$env:PSModulePath` variable; e.g., to install the module in the context of the current user, choose the following parent folders:

* **Windows**:
  * Windows PowerShell: `$HOME\Documents\WindowsPowerShell\Modules`
  * PowerShell Core: `$HOME\Documents\PowerShell\Modules`
* **macOs, Linux** (PowerShell Core): 
  * `$HOME/.local/share/powershell/Modules`

As long as you've cloned into one of the directories listed in the `$env:PSModulePath` variable - copying to some of which requires elevation / `sudo` - and as long your `$PSModuleAutoLoadingPreference` is either has no value (the default) or is set to `All`, calling `ins` or `ie` should import the module on demand.

To explicitly import the module, run `Import-Module <path/to/module-folder>`.

**Example**: Install as a current-user-only module:

Note: Assumes that [`git`](https://git-scm.com/) is installed.

```powershell
# Switch to the parent directory of the current user's modules.
Set-Location $(if ($env:OS -eq 'Windows_NT') { "$HOME\Documents\{0}\Modules" -f ('WindowsPowerShell', 'PowerShell')[[bool]$IsCoreClr] } else { "$HOME/.local/share/powershell/Modules" })
# Clone this repo into subdir. 'Native'; --depth 1 gets only the latest revision.
git clone --depth 1 --quiet https://github.com/mklement0/Native
```

Run `ins -?` to verify that installation succeeded and that the module is loaded on demand:
you should see brief CLI help text.

# License

See [LICENSE.md](./LICENSE.md).

# Changelog

See [CHANGELOG.md](./CHANGELOG.md).
