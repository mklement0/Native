# Changelog

Versioning complies with [semantic versioning (semver)](http://semver.org/).

<!-- RETAIN THIS COMMENT. An entry template for a new version is automatically added each time `Invoke-psake version` is called. Fill in changes afterwards. -->

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
