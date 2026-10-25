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
$script:EmailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

# Recommended standard options. Each option lists its selectable values with a
# short explanation; AllowCustom additionally accepts any typed value.
$script:RecommendedSettings = @(
    @{ Key = 'init.defaultBranch'; Value = 'main'; AllowCustom = $true
       Description = 'Name of the first branch in newly created repositories (git init). Existing repositories are not renamed. Use "main" to match GitHub and most current tooling; "master" was the historical default.'
       Options = @(
           @{ Value = 'main'; Text = 'New repositories start with the branch "main"' }
           @{ Value = 'master'; Text = 'New repositories start with the branch "master"' }
       ) }
    @{ Key = 'core.autocrlf'; Value = 'true'
       Description = 'Line-ending conversion. A .gitattributes file in a repository takes precedence.'
       Options = @(
           @{ Value = 'true'; Text = 'Converts CRLF to LF on commit and LF to CRLF on checkout (recommended on Windows)' }
           @{ Value = 'input'; Text = 'Converts CRLF to LF on commit only; checkouts stay unchanged' }
           @{ Value = 'false'; Text = 'Never converts line endings' }
       ) }
    @{ Key = 'core.longpaths'; Value = 'true'
       Description = 'Allows Git to handle file paths longer than 260 characters on Windows. Without it, deeply nested projects can fail to check out. Windows itself may also need long-path support enabled.'
       Options = @(
           @{ Value = 'true'; Text = 'Enables long paths' }
           @{ Value = 'false'; Text = 'Keeps the 260-character path limit' }
       ) }
    @{ Key = 'fetch.prune'; Value = 'true'
       Description = 'On every fetch or pull, remote-tracking branches that were deleted on the server can be removed locally. Your own local branches are never touched.'
       Options = @(
           @{ Value = 'true'; Text = 'Removes remote-tracking branches that no longer exist on the server' }
           @{ Value = 'false'; Text = 'Keeps stale remote-tracking branches' }
       ) }
    @{ Key = 'pull.rebase'; Value = 'false'
       Description = 'How "git pull" combines remote changes with local commits. Without a value, Git warns on diverging pulls.'
       Options = @(
           @{ Value = 'false'; Text = 'Merges remote changes (creates a merge commit)' }
           @{ Value = 'true'; Text = 'Rebases local commits on top (linear history, rewrites local commits)' }
       ) }
    @{ Key = 'push.autoSetupRemote'; Value = 'true'
       Description = 'The first "git push" of a new branch can automatically create the remote branch and set its upstream, so "--set-upstream" is no longer needed.'
       Options = @(
           @{ Value = 'true'; Text = 'Sets up the remote branch and upstream automatically on the first push' }
           @{ Value = 'false'; Text = 'Requires "git push --set-upstream" for new branches' }
       ) }
    @{ Key = 'format.signOff'; Value = 'true'
       Description = 'Controls the "Signed-off-by: Name <email>" line in patches created with "git format-patch". It does NOT affect normal commits; Git has no setting that signs off every commit automatically.'
       Options = @(
           @{ Value = 'true'; Text = 'Adds a Signed-off-by line to patches from git format-patch' }
           @{ Value = 'false'; Text = 'Adds no Signed-off-by line to patches' }
       ) }
    @{ Key = 'alias.cs'; Value = 'commit --signoff'; AllowCustom = $true
       Description = 'Defines the shortcut "git cs". With "commit --signoff" it creates a commit with a Signed-off-by line (certifying the Developer Certificate of Origin).'
       Options = @(
           @{ Value = 'commit --signoff'; Text = 'Defines "git cs" as "git commit --signoff"' }
       ) }
)

<#
.SYNOPSIS
    Returns a localized console message.

.DESCRIPTION
    Selects German text when German output is active and otherwise uses the
    English source message. Formats the selected text when arguments are given.

.PARAMETER Text
    English source message and localization key.

.PARAMETER Arguments
    Values for formatting placeholders in the message.

.OUTPUTS
    System.String. The localized and optionally formatted message.
#>
function Get-LocalizedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [AllowEmptyCollection()][object[]] $Arguments = @()
    )

    $template = if ($script:OutputLanguage -eq 'de' -and $script:GermanMessages.ContainsKey($Text)) {
        $script:GermanMessages[$Text]
    }
    else { $Text }
    if ($Arguments.Count -gt 0) { return $template -f $Arguments }
    return $template
}

<#
.SYNOPSIS
    Runs a Git command, optionally for a specific repository.

.DESCRIPTION
    Captures command output and checks Git's exit code so failures are reported
    instead of being mistaken for successful configuration.

.PARAMETER Repository
    Root path of the Git repository. Omit for commands independent of a repository.

.PARAMETER Arguments
    Arguments passed to Git.

.OUTPUTS
    System.String[]. Lines emitted by Git.
#>
function Invoke-GitCommand {
    [CmdletBinding()]
    param(
        [string] $Repository,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $prefix = if ($Repository) { @('-C', $Repository) } else { @() }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git @prefix @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw (Get-LocalizedText -Text 'Git command failed (exit code {0}): {1}' -Arguments @($exitCode, $details))
    }
    return $output
}

<#
.SYNOPSIS
    Reads a Git configuration value from one scope.

.DESCRIPTION
    Returns the configured value for a key, or an empty string when the key is
    not set in the requested scope.

.PARAMETER Key
    Git configuration key to read.

.PARAMETER Scope
    Local, Global, or System.

.PARAMETER Repository
    Root path of the Git repository; required for the Local scope.

.OUTPUTS
    System.String. The configured value or an empty string.
#>
function Get-GitConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][ValidateSet('Local', 'Global', 'System')][string] $Scope,
        [string] $Repository
    )

    if ($Scope -eq 'Local' -and -not $Repository) { return '' }
    $prefix = if ($Scope -eq 'Local') { @('-C', $Repository) } else { @() }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $value = @(& git @prefix config ('--' + $Scope.ToLowerInvariant()) --get $Key 2>$null)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    # A missing system config file is not an error for this purpose.
    if ($exitCode -eq 1 -or ($exitCode -ne 0 -and $Scope -eq 'System')) { return '' }
    if ($exitCode -ne 0) {
        throw (Get-LocalizedText -Text 'Could not read Git setting: {0}' -Arguments @($Key))
    }
    return ($value -join [Environment]::NewLine).Trim()
}

<#
.SYNOPSIS
    Writes a Git configuration value to the target scope.

.DESCRIPTION
    Stores a value in the repository-local or global Git configuration.

.PARAMETER Key
    Git configuration key to set.

.PARAMETER Value
    Value to store.

.PARAMETER Scope
    Local or Global.

.PARAMETER Repository
    Root path of the Git repository; required for the Local scope.

.OUTPUTS
    None.
#>
function Set-GitConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Value,
        [Parameter(Mandatory)][ValidateSet('Local', 'Global')][string] $Scope,
        [string] $Repository
    )

    $repositoryArgument = if ($Scope -eq 'Local') { $Repository } else { '' }
    Invoke-GitCommand -Repository $repositoryArgument `
        -Arguments @('config', ('--' + $Scope.ToLowerInvariant()), $Key, $Value) | Out-Null
}

<#
.SYNOPSIS
    Reads a name format of the signed-in Windows account.

.DESCRIPTION
    Calls the Windows GetUserNameEx API, which works for local, Active
    Directory, and Entra ID (Azure AD) sign-ins and returns nothing when the
    format is unavailable.

.PARAMETER Format
    EXTENDED_NAME_FORMAT value: 3 for display name, 8 for user principal name.

.OUTPUTS
    System.String. The name or an empty string.
#>
function Get-AccountNameFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int] $Format)

    try {
        if (-not ('Scriptbox.AccountNames' -as [type])) {
            Add-Type -Namespace 'Scriptbox' -Name 'AccountNames' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("secur32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool GetUserNameEx(int nameFormat, System.Text.StringBuilder userName, ref uint size);
'@
        }
        $builder = [System.Text.StringBuilder]::new(512)
        [uint32] $size = 512
        if ([Scriptbox.AccountNames]::GetUserNameEx($Format, $builder, [ref] $size)) {
            return $builder.ToString().Trim()
        }
    }
    catch {
        Write-Verbose $_.Exception.Message
    }
    return ''
}

<#
.SYNOPSIS
    Looks up the signed-in user in Active Directory.

.DESCRIPTION
    Queries the user's mail and displayName attributes on domain-joined
    computers. Returns empty values when the computer is not domain-joined or
    the directory is unreachable.

.OUTPUTS
    PSCustomObject with DisplayName and Mail properties.
#>
function Get-DirectoryUserInfo {
    [CmdletBinding()]
    param()

    $result = [pscustomobject]@{ DisplayName = ''; Mail = '' }
    if ([Environment]::UserDomainName -eq [Environment]::MachineName) { return $result }
    $searcher = $null
    try {
        Add-Type -AssemblyName System.DirectoryServices
        $account = [Environment]::UserName -replace '([\\*()])', '\$1'
        $searcher = [System.DirectoryServices.DirectorySearcher]::new()
        $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$account))"
        $searcher.ClientTimeout = [TimeSpan]::FromSeconds(5)
        [void] $searcher.PropertiesToLoad.AddRange([string[]] @('mail', 'displayName'))
        $entry = $searcher.FindOne()
        if ($entry) {
            if ($entry.Properties['mail'].Count -gt 0) { $result.Mail = [string] $entry.Properties['mail'][0] }
            if ($entry.Properties['displayName'].Count -gt 0) { $result.DisplayName = [string] $entry.Properties['displayName'][0] }
        }
    }
    catch {
        Write-Verbose $_.Exception.Message
    }
    finally {
        if ($searcher) { $searcher.Dispose() }
    }
    return $result
}

<#
.SYNOPSIS
    Collects name and email candidates for the signed-in user.

.DESCRIPTION
    Combines existing Git settings, Windows/Active Directory display names,
    the directory mail attribute, the user principal name, and signed-in
    Microsoft account addresses. Duplicate values are listed once.

.PARAMETER Key
    user.name or user.email.

.PARAMETER Repository
    Root path of the repository when the target scope is Local.

.OUTPUTS
    PSCustomObject[] with Value and Source properties.
#>
function Get-IdentityCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('user.name', 'user.email')][string] $Key,
        [string] $Repository
    )

    $found = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Value, [string] $Source)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $Value = $Value.Trim()
        if ($Key -eq 'user.email' -and $Value -notmatch $script:EmailPattern) { return }
        if (-not @($found | Where-Object { $_.Value -ieq $Value }).Count) {
            $found.Add([pscustomobject]@{ Value = $Value; Source = $Source })
        }
    }

    $scopes = if ($Scope -eq 'Local') { @('Local', 'Global', 'System') } else { @('Global', 'System') }
    # Existing settings come first so that pressing Enter keeps the former value.
    foreach ($existingScope in $scopes) {
        & $add (Get-GitConfigValue -Key $Key -Scope $existingScope -Repository $Repository) `
            (Get-LocalizedText -Text 'Existing Git setting ({0})' -Arguments @($existingScope))
    }
    $directory = Get-DirectoryUserInfo
    if ($Key -eq 'user.name') {
        & $add $directory.DisplayName (Get-LocalizedText 'Active Directory display name')
        & $add (Get-AccountNameFormat -Format 3) (Get-LocalizedText 'Windows display name')
        try {
            if ([Environment]::UserDomainName -eq [Environment]::MachineName) {
                $local = [ADSI]('WinNT://{0}/{1},user' -f [Environment]::MachineName, [Environment]::UserName)
                & $add ([string] $local.FullName.Value) (Get-LocalizedText 'Windows display name')
            }
        }
        catch { Write-Verbose $_.Exception.Message }
    }
    else {
        & $add $directory.Mail (Get-LocalizedText 'Active Directory email')
        & $add (Get-AccountNameFormat -Format 8) (Get-LocalizedText 'User principal name')
        try {
            $identityKey = 'HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties'
            if (Test-Path -LiteralPath $identityKey) {
                foreach ($item in Get-ChildItem -LiteralPath $identityKey) {
                    & $add $item.PSChildName (Get-LocalizedText 'Microsoft account')
                }
            }
        }
        catch { Write-Verbose $_.Exception.Message }
    }
    return $found.ToArray()
}

<#
.SYNOPSIS
    Tests whether an identity value is acceptable.

.DESCRIPTION
    Names must be non-empty; email addresses must look like a valid address.

.PARAMETER Key
    user.name or user.email.

.PARAMETER Value
    Value to validate.

.OUTPUTS
    System.Boolean. True when the value is acceptable.
#>
function Test-IdentityValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('user.name', 'user.email')][string] $Key,
        [AllowEmptyString()][string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Key -eq 'user.email') { return ($Value.Trim() -match $script:EmailPattern) }
    return $true
}

<#
.SYNOPSIS
    Lets the user choose a candidate or enter a custom identity value.

.DESCRIPTION
    Shows discovered candidates as a numbered list plus a custom option and
    repeats until a valid choice is made. Without candidates, it asks directly.

.PARAMETER Key
    user.name or user.email.

.PARAMETER Candidates
    Discovered choices with Value and Source properties.

.OUTPUTS
    System.String. The chosen value.
#>
function Select-IdentityValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('user.name', 'user.email')][string] $Key,
        [AllowEmptyCollection()][object[]] $Candidates = @()
    )

    $isName = $Key -eq 'user.name'
    $customPrompt = Get-LocalizedText $(if ($isName) { 'Enter the Git author name' } else { 'Enter the Git author email' })
    $invalidMessage = Get-LocalizedText $(if ($isName) { 'Git author name cannot be empty.' } else { 'Enter a non-empty, valid email address.' })

    if ($Candidates.Count -gt 0) {
        Write-Host (Get-LocalizedText $(if ($isName) { 'Choose the Git author name:' } else { 'Choose the Git author email:' })) -ForegroundColor Cyan
        for ($index = 0; $index -lt $Candidates.Count; $index++) {
            Write-Host ('  [{0}] {1} ({2})' -f ($index + 1), $Candidates[$index].Value, $Candidates[$index].Source)
        }
        Write-Host ('  [{0}] {1}' -f ($Candidates.Count + 1), (Get-LocalizedText 'Enter a custom value'))
        while ($true) {
            $answer = (Read-Host -Prompt (Get-LocalizedText 'Selection (default: 1)')).Trim()
            if ($answer -eq '') { $answer = '1' }
            $number = 0
            if (-not [int]::TryParse($answer, [ref] $number) -or $number -lt 1 -or $number -gt ($Candidates.Count + 1)) {
                Write-Warning (Get-LocalizedText 'Invalid selection.')
                continue
            }
            if ($number -le $Candidates.Count) { return $Candidates[$number - 1].Value }
            break
        }
    }
    while ($true) {
        $custom = (Read-Host -Prompt $customPrompt).Trim()
        if (Test-IdentityValue -Key $Key -Value $custom) { return $custom }
        Write-Warning $invalidMessage
    }
}

<#
.SYNOPSIS
    Confirms each recommended standard setting with the user.

.DESCRIPTION
    Asks for every recommended option and lists its selectable values one per
    line with an explanation. The default (Enter) is the value already set in
    the target scope, or the recommendation when none exists. Typing a listed
    value selects it; options that allow custom values also accept any other
    text. '-' leaves the option untouched. Unchanged values are not rewritten,
    so repeated runs change nothing.

.PARAMETER Repository
    Root path of the repository when the target scope is Local.

.OUTPUTS
    None.
#>
function Set-RecommendedGitSettings {
    [CmdletBinding()]
    param([string] $Repository)

    Write-Host (Get-LocalizedText -Text 'Confirm recommended Git settings ({0} scope). Enter keeps the default, - skips.' -Arguments @($Scope)) -ForegroundColor Cyan
    foreach ($setting in $script:RecommendedSettings) {
        $current = Get-GitConfigValue -Key $setting.Key -Scope $Scope -Repository $Repository
        $default = if ($current) { $current } else { $setting.Value }
        $options = [System.Collections.Generic.List[object]]::new()
        $options.AddRange([object[]] $setting.Options)
        if ($current -and -not @($options | Where-Object { $_.Value -ceq $current }).Count) {
            $options.Insert(0, @{ Value = $current; Text = (Get-LocalizedText 'Current value (unchanged)') })
        }

        Write-Host ''
        Write-Host $setting.Key -ForegroundColor Cyan
        Write-Host (Get-LocalizedText $setting.Description)
        foreach ($option in $options) {
            $text = if ($option.Text -ceq (Get-LocalizedText 'Current value (unchanged)')) { $option.Text } else { Get-LocalizedText $option.Text }
            Write-Host ('  [{0}] {1}' -f $option.Value, $text)
        }
        if ($current -and $current -cne $setting.Value) {
            Write-Host (Get-LocalizedText -Text 'Recommended value: {0}' -Arguments @($setting.Value))
        }

        while ($true) {
            $answer = (Read-Host -Prompt (Get-LocalizedText -Text 'Selection (default: {0})' -Arguments @($default))).Trim()
            if ($answer -eq '-') { $value = $null; break }
            if ($answer -eq '') { $value = $default; break }
            $match = @($options | Where-Object { $_.Value -ieq $answer }) | Select-Object -First 1
            if ($match) { $value = $match.Value; break }
            if ($setting.ContainsKey('AllowCustom') -and $setting.AllowCustom) { $value = $answer; break }
            Write-Warning (Get-LocalizedText 'Invalid selection.')
        }
        if ($null -eq $value) { continue }
        if ($value -ceq $current) {
            Write-Host (Get-LocalizedText -Text 'Preserving existing {0}: {1}' -Arguments @($setting.Key, $current))
            continue
        }
        Set-GitConfigValue -Key $setting.Key -Value $value -Scope $Scope -Repository $Repository
        Write-Host (Get-LocalizedText -Text 'Configured {0}: {1}' -Arguments @($setting.Key, $value)) -ForegroundColor Green
    }
}

# --- Resolve and validate the repository ---------------------------------
$repositoryRoot = ''
if ($Scope -eq 'Local') {
    $RepositoryPath = [Environment]::ExpandEnvironmentVariables($RepositoryPath.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
        throw (Get-LocalizedText -Text 'Repository path not found: {0}' -Arguments @($RepositoryPath))
    }
    $repositoryRoot = (Invoke-GitCommand -Repository $RepositoryPath -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
}

# --- Fill identity values -------------------------------------------------
Write-Host (Get-LocalizedText -Text 'Checking Git identity ({0} scope).' -Arguments @($Scope)) -ForegroundColor Cyan
$provided = @{ 'user.name' = $Name; 'user.email' = $Email }
foreach ($key in @('user.name', 'user.email')) {
    $current = Get-GitConfigValue -Key $key -Scope $Scope -Repository $repositoryRoot
    $value = if (-not [string]::IsNullOrWhiteSpace($provided[$key])) {
        $provided[$key].Trim()
    }
    else {
        Select-IdentityValue -Key $key -Candidates @(Get-IdentityCandidates -Key $key -Repository $repositoryRoot)
    }
    if (-not (Test-IdentityValue -Key $key -Value $value)) {
        throw (Get-LocalizedText $(if ($key -eq 'user.name') { 'Git author name cannot be empty.' } else { 'Enter a non-empty, valid email address.' }))
    }
    if ($value -ceq $current) {
        Write-Host (Get-LocalizedText -Text 'Preserving existing {0}: {1}' -Arguments @($key, $current))
        continue
    }
    Set-GitConfigValue -Key $key -Value $value -Scope $Scope -Repository $repositoryRoot
    Write-Host (Get-LocalizedText -Text 'Configured {0}: {1}' -Arguments @($key, $value)) -ForegroundColor Green
}

# --- Recommended standard settings ----------------------------------------
Set-RecommendedGitSettings -Repository $repositoryRoot
