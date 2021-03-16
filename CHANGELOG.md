# Changelog

<!-- RETAIN THIS COMMENT. An entry template for a new version is automatically added each time `Invoke-psake version` is called. Fill in changes afterwards. -->

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
