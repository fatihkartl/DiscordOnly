# Check hashes of packaged executable scripts and C# sources. Does not prove provenance.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestFile,
    [switch]$Quiet
)
$ErrorActionPreference='Stop'
$issues=New-Object System.Collections.Generic.List[string]
$required=@('app/launcher.ps1','app/DiscordOnly.ps1','app/DiscordDnsProxy.ps1',
    'app/DiscordDnsProxy.cs','tools/Repair-All.ps1','tools/Repair-DNS.ps1',
    'tools/Diagnose-DNS.ps1','tools/Test-Integrity.ps1','tools/Security-Check.ps1',
    'Start-Silent.vbs','Start.cmd','Start-Debug.cmd','Security-Check.cmd',
    'Repair-All.cmd','Repair-DNS.cmd','Diagnose-DNS.cmd','launcher/DiscordOnlyLauncher.cs')
try {
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $manifestFull=[IO.Path]::GetFullPath($ManifestFile)
    if (!(Test-Path -LiteralPath $manifestFull -PathType Leaf)) { throw 'Missing security manifest' }
    $entries=@{}
    foreach($line in [IO.File]::ReadAllLines($manifestFull)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -cnotmatch '^([a-f0-9]{64})  ([A-Za-z0-9_./-]+)$') { throw 'Invalid checksum manifest record' }
        $hash=$Matches[1]; $relative=$Matches[2]
        if ($relative.StartsWith('/') -or $relative.Contains('..') -or $entries.ContainsKey($relative)) { throw 'Unsafe or duplicate manifest path' }
        $entries[$relative]=$hash
    }
    foreach($requiredFile in $required) {
        if (!$entries.ContainsKey($requiredFile)) { $issues.Add('Missing manifest entry: '+$requiredFile) }
    }
    foreach($relative in $entries.Keys) {
        $path=Join-Path $rootPath ($relative.Replace('/','\'))
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { $issues.Add('Missing file: '+$relative); continue }
        $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne $entries[$relative]) { $issues.Add('Modified file: '+$relative) }
    }
} catch { $issues.Add('Integrity verification error: '+$_.Exception.Message) }
if (!$Quiet) {
    if ($issues.Count -eq 0) { Write-Host 'INTEGRITY CHECK: matching checksums (not a malware clearance).' -ForegroundColor Green }
    else { foreach($issue in $issues) { Write-Host ('INTEGRITY FAILURE: '+$issue) -ForegroundColor Red } }
}
return ($issues.Count -eq 0)
