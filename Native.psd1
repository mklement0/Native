@{

# Script module or binary module file associated with this manifest.
RootModule = 'Native.psm1'

# Version number of this module.
ModuleVersion = '1.3.2'

# Supported PSEditions: BOTH.
# However, we can't use the `CompatiblePSEditions`entry, because it is 
# only supported in v5.1+.
# CompatiblePSEditions = 'Core', 'Desktop'

# ID used to uniquely identify this module
GUID = 'f7fd420a-47e4-4216-bd57-c88696123608'

# Author of this module
Author = 'Michael Klement <mklement0@gmail.com>'

# Copyright statement for this module
Copyright = '(c) 2020 Michael Klement <mklement0@gmail.com>, released under the [MIT license](http://opensource.org/licenses/MIT)'

# Description of the functionality provided by this module
Description = 'Commands to facilitate native-shell and external-executable calls.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '3.0'

FunctionsToExport = 'Invoke-NativeShell', 'ie', 'iee', 'Debug-ExecutableArguments'
AliasesToExport = 'ins', 'dbea'

CmdletsToExport = @()
VariablesToExport = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = 'native', 'shell', 'invoke', 'invocation', 'executable', 'quoting', 'escaping'

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/mklement0/Native/blob/master/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/mklement0/Native'

        # ReleaseNotes of this module - point this to the changelog section of the read-me
        ReleaseNotes = 'https://github.com/mklement0/Native/blob/master/CHANGELOG.md'

    } # End of PSData hashtable

} # End of PrivateData hashtable

}

