#requires -version 5.1
param([Parameter(Mandatory=$true)][string]$StateRoot)
$ErrorActionPreference='Stop'
[void][IO.Directory]::CreateDirectory($StateRoot)
$ready=Join-Path $StateRoot 'dns-proxy.ready'
$log=Join-Path $StateRoot 'dns-proxy.log'
Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
try {
    $source=Join-Path $PSScriptRoot 'DiscordDnsProxy.cs'
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -ReferencedAssemblies @('System.dll','System.Core.dll') -ErrorAction Stop
    [DiscordOnlyDns.Proxy]::Run($ready,$log)
} catch {
    Add-Content -LiteralPath $log -Value ('['+(Get-Date -Format s)+'] Fatal: '+($_ | Out-String))
    throw
} finally {
    Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
}
