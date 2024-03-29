# Changelog

<!-- RETAIN THIS COMMENT. An entry template for a new version is automatically added each time `Invoke-psake version` is called. Fill in changes afterwards. -->

* **v1.5** (2021-04-30):
  * [enhancement] `\"`-escaping is now also the default in Windows PowerShell, as was already the case in PowerShell Core, which notably now makes `git` calls with embedded double quotes work correctly. The edge cases in which Windows PowerShell neglects to provide enclosing double-quoting are now avoided by using `--%` behind the scenes.
  * [fix] Compatibility with Windows PowerShell v3 and v4 restored.
  * [fix] Workaround for calling batch files whose paths need double-quoting on Windows versions before Windows 10: since double-quoting there breaks the `cmd /c "<batch-file> ... & exit"` invocation used behind the scenes, the short (8.3) version of the path is used, which doesn't require double-quoting.

* **v1.4.2** (2021-04-29):
  * [enhancement] In _Windows PowerShell_, `\"`-escaping is now also used for `git.exe`, which only recognizes this form. (In PowerShell _Core_, `\"`-escaping is used by default anyway.) Note that while this should work in general, Windows PowerShell's limitations prevent passing an argument such as `'"foo bar"` properly, because the resulting escaped `\"foo bar\"` is mistakenly passed as-is rather than as `"\"foo bar\""`. That is, in Windows PowerShell passing an argument whose embedded `"` are at the very start and end isn't supported for those executables where `\"`-escaping must be used, unfortunately. Additionally, `pwsh.exe` now no longer triggers `\"`-escaping, because - unlike `powershell.exe` - it also recognizes `""`-escaping.

* **v1.4.1** (2021-04-22):
  * [fix] Comment-based help for `ie` works again (a syntax problem in v1.4 broke it).

* **v1.4** (2021-04-22):
  * [enhancement] On Windows, `dbea` now supports a `-UseWSH` switch that echoes the arguments via WSH (Windows Script Host); specifically, a temporary VBScript script passed to `cscript.exe` is used.
  * [enhancement] When using `ie` to invoke a script directly or indirectly via WSH (`cscript.exe` or `wscript.exe`), `""`-escaping of embedded `"` chars. is now also employed in PowerShell Core. While WSH supports neither `""` nor `\"`-escaping, `""`-escaping at least preserves argument boundaries correctly, while still stripping the embedded `"`, unfortunately.
  * [fix] Temporary files are now properly cleaned up.

* **v1.3.3** (2021-04-18):
  * [enhancement] `dbea -UseBatchFile`'s diagnostic output now uses `«` and `»` as well, and now also includes the value of `%*`, i.e. the raw command line (without the batch-file path).

* **v1.3.2** (2021-04-16):
  * [enhancement] `dbea`'s diagnostic output now uses `«` and `»` to enclose arguments, for improved visualization.
  * [fix] PowerShell 7.2.0-preview.5 introduced a new experimental feature named `PSNativeCommandArgumentPassing`, aimed at solving the problem that `ie` solves in PowerShell itself.
    However, it currently lacks vital accommodations for CLIs on Windows (see [GitHub issue #15143](https://github.com/PowerShell/PowerShell/issues/15143)).
    This module now also checks for these accommodations and, if they're found missing, deactivates the feature in the module's scope by setting `$PSNativeCommandArgumentPassing` to `'Legacy'`, meaning that this module's workarounds are still being applied on top of the old, broken behavior, so as to provide all necessary accommodations.
  * [fix] Partial double-quoting for `msiexec`-style applications for arguments such as `FOO="bar none"` now works again for batch-file calls (was accidentally broken when exit-code reporting was made reliable).

* **v1.3.1** (2021-04-08):
  * [enhancement] An `ins` invocation that passes separate arguments to the `-CommandLine` argument string now triggers a warning if these arguments aren't being referenced (such as with `$1` / `%1` on Unix / Windows). This alerts the user to accidental invocation of what should be `ins 'echo foo'` as `ins echo foo`.

* **v1.3** (2021-04-06):
  * [enhancement] Reliable exit-code reporting for batch-file calls is now built into `ie`, via `cmd /c "<batch-file> ... & exit"`, courtesy of [this Stack Overflow post](https://stackoverflow.com/q/66975883/45375).

* **v1.2.2** (2021-04-06):
  * [fix] Script block-based PowerShell CLI calls now function properly again.
  * [doc] README updated with guidance for reliable batch-file exit-code reporting via `cmd /c call`

* **v1.2.1** (2021-03-16):
  * [fix] `cmd /c` / `cmd /k` now function correctly with the command line passed as _multiple_ arguments.

* **v1.2** (2021-03-15):
  * [enhancement] Support for calling `cmd.exe` directly with a command line, via `/c` or `/k` - though note that with a single-argument pass-through command line `ie` / `iee` aren't strictly needed.

* **v1.1.1** (2021-03-12):
  * [doc] Clarification re passing arguments that start with a spaceless word followed by `=` (e.g. `a=b`) to batch files.

* **v1.1** (2020-08-29):
  * [enhancement] `ie` now also accepts and resolves *aliases* of external executables.
  * [enhancement] `ie` now also calls `Rscript.exe` with the required `\"`-escaping in Windows PowerShell (in PowerShell Core it always did).

* **v1.0.10** (2020-08-21):
  * [dev] Improved tests, streamlined implementation.

* **v1.0.9** (2020-08-20):
  * [enhancement] For robustness, on PowerShell Core, `""`-escaping of embedded `"` chars. is now only switched to in the presence of `msiexec`-style arguments if `msiexec` and `msdeploy` are being invoked (`cmdkey` doesn't support embedding `"` at all); on Windows PowerShell, `""`-escaping remains the default to favor working around legacy bugs over CLIs that don't support `""`-escaping; see the note about the limitations of escaping of verbatim `"` chars. in the read-me's Known Limitations section.

* **v1.0.8** (2020-08-17):
  * [enhancement] The executable name given is now only looked for as an external executable (command type `Application`), even if other command forms with the same name are present; fixes #3

* **v1.0.7** (2020-08-15):
  * [doc] Clarification added that for technical reasons `ins` / `Invoke-NativeShell` cannot be meaningfully combined with the `&&` and `||` operators.

* **v1.0.6** (2020-08-15):
  * [doc] Clarification added that for technical reasons `ie` cannot be meaningfully combined with the `&&` and `||` operators.

* **v1.0.5** (2020-08-15):
  * [enhancement] On Windows, `<word>=<value>`, `/<word>:<value>` / `-<word>:<value>` now result in `""`-escaping of embedded `"` in both editions.
    If `<value>` has spaces, the argument is passed with double-quoting of the value only (e.g., `<word>="<value>"`), but only in PowerShell versions 5.1 and above (not supported in v3 and v4).

* **v1.0.4** (2020-08-13):
  * [enhancement] `<word>=<value with spaces>` arguments are now always passed as
    `<word>="<value with spaces>"` on Windows; in Windows PowerShell, `""` is now
    used as the default escaping of `"` to better handle edge cases, with `\"` only used for `ruby`, `perl`, `powershell`, and `pwsh`, of necessity.
    In PowerShell Core, there is no problem with `\"` so it is used as the default there, except with batch files and direct calls to `cmd.exe`.
  * [fix] Space-less arguments with embedded `"` are now passed correctly to batch files.
  * [dev] Tests now properly force the module being tested to be the only loaded by that name.
  * [doc] Read-me and comment-based help improvements.

* **v1.0.3** (2020-08-12):
  * [fix] Batch files and therefore the need to escape `"` as `""` are now also correctly detected by `ie` in Windows PowerShell v3 and v4.
  * [dev] Tests amended so they can run from versioned subfolders too.

* **v1.0.2** (2020-08-11):
  * [fix] Aliases `ins` and `dbea` are now also defined in Windows PowerShell v3 and v4.
  * [dev] Fixed tests on Windows PowerShell.

* **v1.0.1** (2020-08-09):
  * Improved module description in the `.psd1` file.

* **v1.0.0** (2020-08-09):
  * Initial release.
