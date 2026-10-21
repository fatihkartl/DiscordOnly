# One-time repository metadata and source-beta release finalization
# This tool only changes GitHub metadata/releases. It does not modify local networking.
# Requires GitHub CLI (gh) and explicit authentication on the maintainer PC.
[CmdletBinding()]
param(
    [string]$Repository = 'fatihkartl/DiscordOnly',
    [string]$Tag = 'v0.3.4'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) is missing: https://cli.github.com/'
}
& gh auth status -h github.com
if ($LASTEXITCODE -ne 0) { throw 'Log in using: gh auth login' }

$description = 'Discord-focused Windows DNS + DPI manager | Encrypted DNS, safe profiles, tray controls & diagnostics'
& gh repo edit $Repository --description $description
if ($LASTEXITCODE -ne 0) { throw 'Failed to update repository description' }

$topics = @(
    'discord', 'discord-bypass', 'discord-unblock', 'dpi-bypass',
    'deep-packet-inspection', 'windows', 'windows-11', 'windows-10',
    'powershell', 'dns-over-https', 'network-tools', 'winws',
    'windivert', 'nrpt', 'anti-censorship', 'discord-voice',
    'network-diagnostics', 'system-tray', 'dns-proxy', 'turkey'
)
$payload = @{ names = $topics } | ConvertTo-Json -Depth 3
$tmp = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($tmp, $payload, (New-Object System.Text.UTF8Encoding $false))
    & gh api -X PUT "repos/$Repository/topics" --input $tmp | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to set GitHub topics' }
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

& gh release view $Tag -R $Repository --json tagName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    $notes = @'
DiscordOnly v0.3.4 (beta, source-only initially).

**The source is available in this repository.**
This GitHub Release does NOT yet contain a verified Windows executable.
When GitHub Actions runners become available, the verified upstream engine and Windows offline bundle can be built and uploaded.

- Temporary Discord-focused DNS/NRPT + DPI strategies
- Automatic Discord launch and conservative profile selection
- Safe tray Exit leaves Discord running
- Real voice, ISP and game-network compatibility remain unverified

Use the source ZIP and documentation for installation, or wait for the CI-produced Windows package.
'@
    $notesFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($notesFile, $notes, (New-Object System.Text.UTF8Encoding $false))
        & gh release create $Tag -R $Repository --target main --title 'DiscordOnly v0.3.4 - Source Beta' --notes-file $notesFile --prerelease
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create beta release' }
    }
    finally {
        Remove-Item $notesFile -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "Release $Tag already exists - leaving it unchanged."
}

Write-Host "Repository metadata and source beta release configured: https://github.com/$Repository"
