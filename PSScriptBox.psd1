# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PSScriptBox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

@{
    RootModule = 'PSScriptBox.psm1'
    ModuleVersion = '0.1.0'
    GUID = '026168fb-4763-4c3e-bb83-310b231ed132'
    Author = 'PSScriptBox contributors'
    CompanyName = 'PSScriptBox contributors'
    Copyright = '(c) 2026 PSScriptBox contributors. All rights reserved.'
    Description = 'PowerShell utilities for PDF and media processing, Git setup, and local Nextcloud workflows.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'ConvertTo-SearchablePdf'
        'Copy-UserDataToNextcloud'
        'Find-PdfsWithoutTextLayer'
        'Initialize-GitConfiguration'
        'Optimize-MediaSize'
        'Optimize-PdfSize'
        'Remove-LivePhotos'
        'Remove-MediaBackups'
        'Remove-MigratedUserData'
        'Remove-ObsoleteGitBranches'
        'Remove-PdfBackups'
        'Repair-PdfObjectStreams'
        'Restore-MediaDate'
        'Restore-PdfOriginals'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PDF', 'Media', 'Git', 'Nextcloud', 'Utilities')
            ProjectUri = 'https://github.com/johkoenig/PSScriptBox'
            LicenseUri = 'https://github.com/johkoenig/PSScriptBox/blob/main/LICENSE.md'
        }
    }
}
