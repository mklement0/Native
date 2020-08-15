# Changelog

Versioning complies with [semantic versioning (semver)](http://semver.org/).

<!-- RETAIN THIS COMMENT. An entry template for a new version is automatically added each time `Invoke-psake version` is called. Fill in changes afterwards. -->

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
