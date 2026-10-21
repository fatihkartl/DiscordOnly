#requires -version 5.1
# Safe crash recovery for DiscordOnly v0.3.2: only the recorded, identity-matched
# winws/DNS worker and explicitly tagged DiscordOnly NRPT rules are touched.
$ErrorActionPreference='Stop'
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=(New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$admin) {
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList ('-NoExit -NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'"')
    return
}
$root=Join-Path $env:LOCALAPPDATA 'DiscordOnly'
$errors=New-Object 'System.Collections.Generic.List[string]'
$created=$false
$mutex=[System.Threading.Mutex]::new($true,'Local\DiscordOnly_DPI_Manager_2026',[ref]$created)
if (!$created) {
    $mutex.Dispose()
    Write-Error 'DiscordOnly is open. Exit it from the tray before running this recovery tool.'
    exit 1
}
function Same-Path([string]$a,[string]$b) {
    try { return [IO.Path]::GetFullPath($a).TrimEnd('\') -ieq [IO.Path]::GetFullPath($b).TrimEnd('\') }
    catch { return $false }
}
function Stop-Recorded([string]$File,[string]$Kind) {
    if (!(Test-Path -LiteralPath $File)) { return }
    $record=Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    if (!$record -or !$record.Pid -or !$record.StartUtc) { throw "$Kind owner record is invalid; preserved for investigation." }
    $p=Get-Process -Id ([int]$record.Pid) -ErrorAction SilentlyContinue
    if ($null -eq $p) {
        Remove-Item -LiteralPath $File -Force -ErrorAction Stop
        Write-Host "$Kind already stopped; removed stale ownership record."
        return
    }
    $expected=[datetime]::Parse([string]$record.StartUtc).ToUniversalTime()
    $cim=Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $p.Id) -ErrorAction Stop
    if ([math]::Abs(($p.StartTime.ToUniversalTime()-$expected).TotalSeconds) -gt 2) {
        throw "$Kind process ID has been reused. Refusing to stop a different process."
    }
    if ($Kind -eq 'winws') {
        $expectedExe=Join-Path $root 'engine\bin\winws.exe'
        if ($p.ProcessName -ine 'winws' -or !(Same-Path ([string]$cim.ExecutablePath) $expectedExe)) {
            throw 'winws process identity/path mismatch. Refusing to stop it.'
        }
    } else {
        $expectedScript=[string]$record.ProxyScript
        if ($p.ProcessName -notin @('powershell','pwsh') -or
            (Split-Path -Leaf $expectedScript) -ine 'DiscordDnsProxy.ps1' -or
            ([string]$cim.CommandLine).IndexOf([IO.Path]::GetFullPath($expectedScript),[StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw 'DNS worker identity/command line mismatch. Refusing to stop it.'
        }
    }
    Stop-Process -Id $p.Id -Force -ErrorAction Stop
    [void]$p.WaitForExit(3000)
    $p.Refresh()
    if (!$p.HasExited) { throw "$Kind process did not exit." }
    Remove-Item -LiteralPath $File -Force -ErrorAction Stop
    Write-Host "Stopped owned $Kind process PID $($p.Id)." -ForegroundColor Green
}
try {
    try { Stop-Recorded (Join-Path $root 'owned.json') 'winws' }
    catch { $errors.Add($_.Exception.Message) }
    # Remove the NRPT rule BEFORE stopping its local DNS server.
    $label='DiscordOnly - Temporary Discord DNS (managed)'
    $comment='DiscordOnly local DoH bridge; removed on STOP'
    $dnsRulesClean=$false
    try {
        $rules=@(Get-DnsClientNrptRule -ErrorAction Stop | Where-Object {
            $_.DisplayName -ceq $label -and $_.Comment -ceq $comment
        })
        foreach ($rule in $rules) {
            Remove-DnsClientNrptRule -Name ([string]$rule.Name) -Force -ErrorAction Stop
            Write-Host ('Removed own DNS rule: '+$rule.Name) -ForegroundColor Green
        }
        $remaining=@(Get-DnsClientNrptRule -ErrorAction Stop | Where-Object {
            $_.DisplayName -ceq $label -and $_.Comment -ceq $comment
        })
        if ($remaining.Count -gt 0) { throw 'DiscordOnly NRPT rules still exist.' }
        $dnsRulesClean=$true
    } catch { $errors.Add('NRPT cleanup: '+$_.Exception.Message) }
    if ($dnsRulesClean) {
        try { Clear-DnsClientCache -ErrorAction Stop | Out-Null }
        catch { Write-Warning ('DNS cache flush failed: '+$_.Exception.Message) }
        try {
            Stop-Recorded (Join-Path $root 'owned-dns.json') 'DNS'
            Remove-Item -LiteralPath (Join-Path $root 'dns-proxy.ready') -Force -ErrorAction SilentlyContinue
        } catch { $errors.Add('DNS proxy cleanup: '+$_.Exception.Message) }
    } else {
        Write-Warning 'DNS worker left running intentionally; NRPT removal was not verified.'
    }
    if ($errors.Count -gt 0) {
        foreach ($e in $errors) { Write-Warning $e }
        Write-Host 'Cleanup INCOMPLETE. No unrelated process was killed. Retry after resolving errors.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Verified cleanup complete: own DPI/DNS processes stopped and own NRPT removed.' -ForegroundColor Green
    Write-Host 'Adapter DNS, gateway, proxy, firewall, saved preferences and engine files were untouched.'
} finally {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
