# User-initiated security diagnostics; never disables or bypasses antivirus.
[CmdletBinding()]
param([switch]$ScanWithDefender)
$ErrorActionPreference='Continue'
$root=Split-Path -Parent $PSScriptRoot
$reportFolder=Join-Path $env:LOCALAPPDATA 'DiscordOnly'
[void][IO.Directory]::CreateDirectory($reportFolder)
$report=Join-Path $reportFolder 'security-check.txt'
$lines=New-Object System.Collections.Generic.List[string]
function Report([string]$Message) {
    Write-Host $Message
    $script:lines.Add($Message)
}
Report ('DiscordOnly security report - '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Report 'This check cannot certify that any file is virus-free.'
$ok=& (Join-Path $PSScriptRoot 'Test-Integrity.ps1') -Root $root -ManifestFile (Join-Path $root 'security\manifest.sha256') -Quiet
if ($ok -eq $true) { Report 'INTEGRITY: PASS (local source checksums only; manifest is not signed).' }
else { Report 'INTEGRITY: FAILED - Do not run the application until reinstalled from a trusted source.' }
Report ''
Report 'Installed antivirus products (Windows Security Center, when available):'
try {
    $products=@(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntivirusProduct -ErrorAction Stop)
    if ($products.Count -eq 0) { Report 'No product reported here. Verify in Windows Security manually.' }
    else { foreach($p in $products) { Report ('- '+$p.displayName+' (reported productState='+$p.productState+')') } }
} catch { Report ('Windows Security Center inventory unavailable: '+$_.Exception.Message) }
$defenderActive=$false
try {
    $d=Get-MpComputerStatus -ErrorAction Stop
    $defenderActive=[bool]($d.AMServiceEnabled -and $d.AntivirusEnabled -and $d.RealTimeProtectionEnabled)
    Report ('Microsoft Defender AV active: '+$defenderActive)
} catch { Report ('Microsoft Defender status unavailable: '+$_.Exception.Message) }
if ($ScanWithDefender) {
    if ($defenderActive -and (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) {
        Report 'Starting Microsoft Defender CUSTOM scan of project directory...'
        try {
            Start-MpScan -ScanType CustomScan -ScanPath $root -ErrorAction Stop
            $cachedEngine=Join-Path $reportFolder 'engine'
            if (Test-Path -LiteralPath $cachedEngine -PathType Container) {
                Report 'Starting Defender CUSTOM scan of cached DPI engine...'
                Start-MpScan -ScanType CustomScan -ScanPath $cachedEngine -ErrorAction Stop
            }
            Report 'Defender scan command finished; CHECK WINDOWS SECURITY PROTECTION HISTORY for detections.'
        } catch { Report ('DEFENDER SCAN FAILED: '+$_.Exception.Message) }
    } else {
        Report 'DEFENDER SCAN SKIPPED: Defender is inactive/unavailable. Use your active antivirus (e.g. Kaspersky) to scan the project AND cached engine folder manually.'
    }
}
$engine=Join-Path $reportFolder 'engine\bin\winws.exe'
if (Test-Path -LiteralPath $engine -PathType Leaf) {
    try {
        $hash=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
        Report ('Installed winws.exe SHA256: '+$hash)
        Report 'Engine hash is informational; compare against a trusted upstream artifact. Existing cached binaries have not been authenticated by this report.'
    } catch { Report ('Could not hash installed engine: '+$_.Exception.Message) }
}
Report ''
Report 'WARNING: Any malware warning or quarantine is a STOP condition. Do not add exclusions or switch off antivirus.'
Report 'For Kaspersky alerts, use Kaspersky quarantine/event details; Defender may be inactive when Kaspersky is installed.'
Report 'Review this report and your antivirus scan result together. No universal clean verdict is issued.'
try {
    [IO.File]::WriteAllLines($report,$lines.ToArray(),[Text.Encoding]::UTF8)
    Report ('Report saved: '+$report)
} catch { Write-Host ('Unable to save security report: '+$_.Exception.Message) -ForegroundColor Red }
if ($ok -ne $true) { exit 2 }
