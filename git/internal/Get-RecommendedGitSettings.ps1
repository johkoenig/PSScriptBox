<#
.SYNOPSIS
    Provides the catalog of recommended Git standard settings.

.DESCRIPTION
    Defines Get-RecommendedGitSettings. The catalog lists each setting with its
    recommended value, an English explanation, and the selectable options.

.NOTES
    Dependencies: Windows PowerShell 5.1 or PowerShell 7.
#>

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 scriptbox contributors
# Contributors:
# - Johannes Koenig <dev@jokoenig.de>

<#
.SYNOPSIS
    Returns the recommended Git standard settings.

.DESCRIPTION
    Each entry is a hashtable with Key, Value (recommended value), Description
    and Options (each with Value and Text). AllowCustom is set on entries that
    accept any typed value. Descriptions and option texts are English source
    strings; the caller localizes them.

.OUTPUTS
    System.Collections.Hashtable[]. The catalog entries in display order.
#>
function Get-RecommendedGitSettings {
    [CmdletBinding()]
    param()

    return @(
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
}
