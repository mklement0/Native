@{

# Script module or binary module file associated with this manifest.
RootModule = 'NativeShell.psm1'

# Version number of this module.
ModuleVersion = '0.1.0'

# Supported PSEditions
CompatiblePSEditions = @( 'Core', 'Desktop' )

# ID used to uniquely identify this module
GUID = 'f7fd420a-47e4-4216-bd57-c88696123608'

# Author of this module
Author = 'Michael Klement <mklement0@gmail.com>'

# Copyright statement for this module
Copyright = '(c) 2020 Michael Klement <mklement0@gmail.com>, released under the [MIT license](http://opensource.org/licenses/MIT)'

# Description of the functionality provided by this module
Description = 'Functionality related to passing command lines to the native shell for execution.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '2.0'

FunctionsToExport = 'Invoke-NativeShell', 'inp'
AliasesToExport = 'ins'

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.


# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        Tags = 'clipboard','text','cross-platform'

        # A URL to the license for this module.
        LicenseUri = 'https://github.com/mklement0/NativeShell/blob/master/LICENSE.md'

        # A URL to the main website for this project.
        ProjectUri = 'https://github.com/mklement0/NativeShell'

        # ReleaseNotes of this module - point this to the changelog section of the read-me
        ReleaseNotes = 'https://github.com/mklement0/NativeShell/blob/master/CHANGELOG.md'

    } # End of PSData hashtable

} # End of PrivateData hashtable

}

