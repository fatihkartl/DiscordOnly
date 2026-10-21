# Run manually when you want to publish this source project to your OWN GitHub account.
# Requires Git + GitHub CLI. Explicit confirmation required.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is missing. Install https://git-scm.com/' }
if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI is missing. Install https://cli.github.com/' }
& gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Log into GitHub first with gh auth login.' }
$repo = Read-Host 'Repository name [discord-only-dpi-manager]'
if (!$repo) { $repo = 'discord-only-dpi-manager' }
if ($repo -cnotmatch '^[A-Za-z0-9._-]+$') { throw 'Invalid repository name.' }
Write-Host "This will create a PUBLIC repository '$repo' and push all project source files."
$answer = Read-Host 'Type PUBLISH to confirm'
if ($answer -cne 'PUBLISH') { Write-Host 'Cancelled'; return }
if (!(Test-Path '.git')) { & git init -b main; if ($LASTEXITCODE -ne 0) { throw 'git init failed' } }
& git add Start.cmd app README.md LICENSE THIRD_PARTY_NOTICES.md Publish-GitHub.ps1 tests .github .gitignore
if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
& git commit -m 'Initial DiscordOnly Windows manager source'
if ($LASTEXITCODE -ne 0) { Write-Host 'No new commit (maybe changes already committed). Continuing.' }
& gh repo create $repo --public --source . --remote origin --push
if ($LASTEXITCODE -ne 0) { throw 'Could not create/push repository. Check GitHub permissions.' }
Write-Host 'GitHub repo created and pushed.'
