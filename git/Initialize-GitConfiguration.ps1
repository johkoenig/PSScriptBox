#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes the Git author identity and optional standard settings.

.DESCRIPTION
    Configures user.name and user.email for the selected scope
    (repository-local by default, or global). For each value the script offers
    discovered choices and a custom entry; an existing setting is listed first
    and is the default, so pressing Enter keeps it:
    - Name: existing Git settings (local, global, system), the account display
      name (Windows or Active Directory), or a custom value.
    - Email: existing Git settings, the Active Directory mail attribute, the
      user principal name, the signed-in Microsoft account, or a custom value.
    Afterwards every recommended standard option (default branch, line endings,
    pull/push behavior, sign-off helpers) is confirmed individually; the
    default is the existing value, or the recommendation when none is set.
    No personal information is stored in this script; every value is
    discovered at run time or supplied by the user.

.PARAMETER RepositoryPath
    Path inside the Git repository to configure when -Scope is Local. Defaults
    to the current directory. Ignored for the Global scope.

.PARAMETER Scope
    Configuration scope to write: Local (repository, default) or Global (all
    repositories of the current user).

.PARAMETER Name
    Name to use instead of the interactive choice for user.name.

.PARAMETER Email
    Email address to use instead of the interactive choice for user.email.

.PARAMETER EnglishOutput
    Forces English console output regardless of the Windows display language.

.EXAMPLE
    .\Initialize-GitConfiguration.ps1
    Offers identity choices and confirms recommended settings for the
    repository in the current directory.

.EXAMPLE
    .\Initialize-GitConfiguration.ps1 -Scope Global
    Configures the global identity and settings for the current user.

.EXAMPLE
    .\Initialize-GitConfiguration.ps1 -RepositoryPath 'C:\src\project' -Name 'Jane Doe' -Email 'jane@example.com'
    Sets the identity for the specified repository without identity prompts.

.NOTES
    Dependencies: Windows PowerShell 5.1 or later and Git for Windows.
    Active Directory lookups run only on domain-joined computers and fail
    silently when no directory is reachable. Git has no setting that adds a
    Signed-off-by trailer to every commit; the recommended settings include
    format.signOff and an alias 'cs' (commit --signoff) instead.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This user-facing script provides localized, color-coded console output.'
)]
[CmdletBinding()]
param(
    [string] $RepositoryPath = (Get-Location).Path,

    [ValidateSet('Local', 'Global')]
    [string] $Scope = 'Local',

    [string] $Name,

    [string] $Email,

    [switch] $EnglishOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:OutputLanguage = if (
    $EnglishOutput -or [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -ne 'de'
) { 'en' } else { 'de' }
$script:GermanMessages = if ($script:OutputLanguage -eq 'de') {
    Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'l10n\de-DE\Messages.psd1')
}
else { @{} }
. (Join-Path $PSScriptRoot '..\common\internal\Get-LocalizedText.ps1')
. (Join-Path $PSScriptRoot 'internal\Invoke-GitCommand.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-GitConfigValue.ps1')
. (Join-Path $PSScriptRoot 'internal\Set-GitConfigValue.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-AccountNameFormat.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-DirectoryUserInfo.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-LocalAccountFullName.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-MicrosoftAccountName.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-IdentitySourceEntry.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-IdentityCandidates.ps1')
. (Join-Path $PSScriptRoot 'internal\Test-IdentityValue.ps1')
. (Join-Path $PSScriptRoot 'internal\Select-IdentityValue.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-RecommendedGitSettings.ps1')
. (Join-Path $PSScriptRoot 'internal\Get-RecommendedSettingOption.ps1')
. (Join-Path $PSScriptRoot 'internal\Resolve-RecommendedSettingAnswer.ps1')
. (Join-Path $PSScriptRoot 'internal\Set-RecommendedGitSettings.ps1')

# --- Banner ---------------------------------------------------------------
$headerLines = @(
    '       .-------------------------------------------.'
    '      /                                           /|'
    '     /___________________________________________/ |'
    '     |  .-------------------------------------.  | |'
    '     |  | GIT CONFIGURATION                   |  | |'
    '     |  | IDENTITY / STANDARD SETTINGS        |  | /'
    '     |  ''-------------------------------------''  |/'
    '     ''-------------------------------------------'''
)

Write-Host ''
foreach ($headerLine in $headerLines) {
    Write-Host $headerLine -ForegroundColor Cyan
}
Write-Host (Get-LocalizedText '  Sets the Git author identity and confirms recommended standard settings.') -ForegroundColor Cyan
Write-Host ''

try {
# --- Resolve and validate the repository ---------------------------------
    $repositoryRoot = ''
    if ($Scope -eq 'Local') {
        $RepositoryPath = [Environment]::ExpandEnvironmentVariables($RepositoryPath.Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
            throw (Get-LocalizedText -Text 'Repository path not found: {0}' -Arguments @($RepositoryPath))
        }
        $repositoryRoot = (Invoke-GitCommand -Repository $RepositoryPath -Arguments @('rev-parse', '--show-toplevel') -Language $script:OutputLanguage -Messages $script:GermanMessages | Select-Object -First 1).Trim()
    }

    # --- Fill identity values -------------------------------------------------
    Write-Host (Get-LocalizedText -Text 'Checking Git identity ({0} scope).' -Arguments @($Scope)) -ForegroundColor Cyan
    $provided = @{ 'user.name' = $Name; 'user.email' = $Email }
    foreach ($key in @('user.name', 'user.email')) {
        $current = Get-GitConfigValue -Key $key -Scope $Scope -Repository $repositoryRoot -Language $script:OutputLanguage -Messages $script:GermanMessages
        $value = $null
        if (-not [string]::IsNullOrWhiteSpace($provided[$key])) {
            $value = $provided[$key].Trim()
        }
        else {
            $directory = Get-DirectoryUserInfo -UserName ([Environment]::UserName) `
                -UserDomainName ([Environment]::UserDomainName) -MachineName ([Environment]::MachineName)
            $entries = Get-IdentitySourceEntry -Key $key -Scope $Scope -Repository $repositoryRoot `
                -UserName ([Environment]::UserName) -UserDomainName ([Environment]::UserDomainName) `
                -MachineName ([Environment]::MachineName) -DirectoryInfo $directory `
                -Language $script:OutputLanguage -Messages $script:GermanMessages
            $candidates = @(Get-IdentityCandidates -Key $key -Entries $entries `
                    -Language $script:OutputLanguage -Messages $script:GermanMessages)
            $customPrompt = Get-LocalizedText $(if ($key -eq 'user.name') { 'Enter the Git author name' } else { 'Enter the Git author email' })
            $invalidMessage = Get-LocalizedText $(if ($key -eq 'user.name') { 'Git author name cannot be empty.' } else { 'Enter a non-empty, valid email address.' })

            if ($candidates.Count -gt 0) {
                Write-Host (Get-LocalizedText $(if ($key -eq 'user.name') { 'Choose the Git author name:' } else { 'Choose the Git author email:' })) -ForegroundColor Cyan
                for ($index = 0; $index -lt $candidates.Count; $index++) {
                    Write-Host ('  [{0}] {1} ({2})' -f ($index + 1), $candidates[$index].Value, $candidates[$index].Source)
                }
                Write-Host ('  [{0}] {1}' -f ($candidates.Count + 1), (Get-LocalizedText 'Enter a custom value'))
                do {
                    $choice = Select-IdentityValue -Candidates $candidates -Answer (Read-Host -Prompt (Get-LocalizedText 'Selection (default: 1)'))
                    if ($choice.Kind -eq 'Invalid') { Write-Warning (Get-LocalizedText 'Invalid selection.') }
                } while ($choice.Kind -eq 'Invalid')
                if ($choice.Kind -eq 'Candidate') { $value = $choice.Value }
            }
            while ($null -eq $value) {
                $custom = (Read-Host -Prompt $customPrompt).Trim()
                if (Test-IdentityValue -Key $key -Value $custom) { $value = $custom }
                else { Write-Warning $invalidMessage }
            }
        }
        if (-not (Test-IdentityValue -Key $key -Value $value)) {
            throw (Get-LocalizedText $(if ($key -eq 'user.name') { 'Git author name cannot be empty.' } else { 'Enter a non-empty, valid email address.' }))
        }
        if ($value -ceq $current) {
            Write-Host (Get-LocalizedText -Text 'Preserving existing {0}: {1}' -Arguments @($key, $current))
            continue
        }
        Set-GitConfigValue -Key $key -Value $value -Scope $Scope -Repository $repositoryRoot -Language $script:OutputLanguage -Messages $script:GermanMessages
        Write-Host (Get-LocalizedText -Text 'Configured {0}: {1}' -Arguments @($key, $value)) -ForegroundColor Green
    }

    # --- Recommended standard settings ----------------------------------------
    Write-Host (Get-LocalizedText -Text 'Confirm recommended Git settings ({0} scope). Enter keeps the default, - skips.' -Arguments @($Scope)) -ForegroundColor Cyan
    foreach ($setting in Get-RecommendedGitSettings) {
        $current = Get-GitConfigValue -Key $setting.Key -Scope $Scope -Repository $repositoryRoot -Language $script:OutputLanguage -Messages $script:GermanMessages
        $default = if ($current) { $current } else { $setting.Value }
        $options = @(Get-RecommendedSettingOption -Options $setting.Options -Current $current `
                -Language $script:OutputLanguage -Messages $script:GermanMessages)

        Write-Host ''
        Write-Host $setting.Key -ForegroundColor Cyan
        Write-Host (Get-LocalizedText $setting.Description)
        foreach ($option in $options) {
            Write-Host ('  [{0}] {1}' -f $option.Value, $option.Text)
        }
        if ($current -and $current -cne $setting.Value) {
            Write-Host (Get-LocalizedText -Text 'Recommended value: {0}' -Arguments @($setting.Value))
        }

        do {
            $answer = Read-Host -Prompt (Get-LocalizedText -Text 'Selection (default: {0})' -Arguments @($default))
            $choice = Resolve-RecommendedSettingAnswer -Answer $answer -Default $default -Options $options `
                -AllowCustom:($setting.ContainsKey('AllowCustom') -and [bool] $setting.AllowCustom)
            if ($choice.Kind -eq 'Invalid') { Write-Warning (Get-LocalizedText 'Invalid selection.') }
        } while ($choice.Kind -eq 'Invalid')

        $change = [pscustomobject]@{ Key = $setting.Key; Value = $choice.Value }
        foreach ($result in Set-RecommendedGitSettings -Changes @($change) -Scope $Scope -Repository $repositoryRoot `
                -Language $script:OutputLanguage -Messages $script:GermanMessages) {
            switch ($result.Status) {
                'Preserved' { Write-Host (Get-LocalizedText -Text 'Preserving existing {0}: {1}' -Arguments @($result.Key, $result.Current)) }
                'Configured' { Write-Host (Get-LocalizedText -Text 'Configured {0}: {1}' -Arguments @($result.Key, $result.Value)) -ForegroundColor Green }
            }
        }
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
