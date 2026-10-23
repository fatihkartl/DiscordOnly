#requires -version 5.1
# DiscordOnly 0.3.4 - safe HTTPS fallback; never rotate solely because Discord UI is slow.
# Windows 10/11 (PowerShell 5.1). Uses temporary NRPT rules for Discord hostnames only.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Version = '0.3.5'
$script:StateRoot = Join-Path $env:LOCALAPPDATA 'DiscordOnly'
$script:EngineRoot = Join-Path $script:StateRoot 'engine'
$script:Bin = Join-Path $script:EngineRoot 'bin'
$script:RuntimeFile = Join-Path $script:StateRoot 'owned.json'
$script:DnsRuntimeFile = Join-Path $script:StateRoot 'owned-dns.json'
$script:DnsReadyFile = Join-Path $script:StateRoot 'dns-proxy.ready'
$script:DnsRuleLabel = 'DiscordOnly - Temporary Discord DNS (managed)'
$script:DnsDomains = @('discord.com','discord.gg','discordapp.com','discordapp.net','discord.media','discordcdn.com','discordstatus.com')
$script:SettingsFile = Join-Path $script:StateRoot 'settings.json'
$script:LogFile = Join-Path $script:StateRoot 'app.log'
$script:ZipUrl = 'https://github.com/Flowseal/zapret-discord-youtube/releases/download/1.10.4/zapret-discord-youtube-1.10.4.zip'
$script:ZipSha256 = '291af673bd0238506f9548e0e94ca0abf244000f4c9a06960544fb01c5f97b34'
$script:Closing = $false
$script:CleanShutdown = $false
$script:ShownTrayTip = $false
$script:InstanceMutex = $null
$script:LastKnownRunning = $false
$script:DnsActive = $false
$script:AutoTrial = $null
$script:TrialTimer = $null
$script:ChangingProfileAutomatically = $false
$script:ConflictDeclined = $false
# Initialize script-scope UI variables before the try/finally cleanup path.
$script:Form = $null
$script:Tray = $null
$script:LogBox = $null
$script:StatusLabel = $null
[void][System.IO.Directory]::CreateDirectory($script:StateRoot)

function Log([string]$Message) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    if ($script:LogBox -and !$script:LogBox.IsDisposed) {
        $script:LogBox.AppendText($line + [Environment]::NewLine)
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
    }
}
function Load-Json([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}
function Save-Json([string]$Path, $Value) {
    $temp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Exact-Path([string]$Path) {
    try { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return '' }
}
function Owned-Process {
    $owned = Load-Json $script:RuntimeFile
    if ($null -eq $owned) { return $null }
    try {
        $p = Get-Process -Id ([int]$owned.Pid) -ErrorAction Stop
        if ($p.ProcessName -ine 'winws') { return $null }
        $expected = [datetime]::Parse([string]$owned.StartUtc).ToUniversalTime()
        $actual = $p.StartTime.ToUniversalTime()
        if ([math]::Abs(($actual - $expected).TotalSeconds) -gt 2) { return $null }
        $cim = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop
        if ((Exact-Path ([string]$cim.ExecutablePath)) -ine (Exact-Path (Join-Path $script:Bin 'winws.exe'))) { return $null }
        return $p
    } catch { return $null }
}
# DNS isolation strategy: the Windows Name Resolution Policy Table routes ONLY
# Discord hostnames to our 127.0.0.1 DNS listener. That listener forwards queries
# over HTTPS with the OS TLS certificate checks still enabled. Adapter DNS, hosts,
# proxies, default gateway, and firewall rules are not changed.
function Owned-DnsProcess {
    $owned=Load-Json $script:DnsRuntimeFile
    if ($null -eq $owned) { return $null }
    try {
        $p=Get-Process -Id ([int]$owned.Pid) -ErrorAction Stop
        if ($p.ProcessName -notin @('powershell','pwsh')) { return $null }
        $expected=[datetime]::Parse([string]$owned.StartUtc).ToUniversalTime()
        if ([math]::Abs(($p.StartTime.ToUniversalTime()-$expected).TotalSeconds) -gt 2) { return $null }
        $cim=Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $p.Id) -ErrorAction Stop
        $expectedScript=Exact-Path ([string]$owned.ProxyScript)
        if (!$expectedScript -or (Split-Path -Leaf $expectedScript) -ine 'DiscordDnsProxy.ps1') { return $null }
        if (([string]$cim.CommandLine).IndexOf($expectedScript,[StringComparison]::OrdinalIgnoreCase) -lt 0) { return $null }
        return $p
    } catch { return $null }
}
function Remove-OwnNrptRules {
    if (!(Get-Command Get-DnsClientNrptRule -ErrorAction SilentlyContinue)) { return }
    $rules=@(Get-DnsClientNrptRule -ErrorAction Stop | Where-Object {
        $_.DisplayName -ceq $script:DnsRuleLabel -and $_.Comment -ceq 'DiscordOnly local DoH bridge; removed on STOP'
    })
    foreach ($rule in $rules) {
        # Never delete an existing user/GPO rule: require our exact display name AND comment.
        Remove-DnsClientNrptRule -Name ([string]$rule.Name) -Force -ErrorAction Stop
    }
    if ($rules.Count -gt 0) { Log ('Removed {0} DiscordOnly NRPT rule(s).' -f $rules.Count) }
}
function Clear-DnsCacheSafe {
    # Cache invalidation is global but brief; no adapter DNS settings are changed.
    try { Clear-DnsClientCache -ErrorAction Stop | Out-Null } catch { Log ('Could not flush the DNS cache: '+$_.Exception.Message) }
}
function Stop-DnsRoute {
    # Never strand Windows NRPT pointing at a stopped local DNS proxy.
    # Retain ownership metadata if a process cannot be verified/stopped.
    Remove-OwnNrptRules
    Clear-DnsCacheSafe
    $p=Owned-DnsProcess
    if ($null -ne $p) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            [void]$p.WaitForExit(3000)
            $p.Refresh()
            if (!$p.HasExited) { throw ('DNS proxy PID {0} did not exit.' -f $p.Id) }
            Log ('Stopped own DNS proxy PID {0}' -f $p.Id)
        } catch {
            Log ('Could not stop own DNS proxy: '+$_.Exception.Message)
            throw
        }
    } elseif (Test-Path -LiteralPath $script:DnsRuntimeFile) {
        $record=Load-Json $script:DnsRuntimeFile
        if ($null -eq $record -or $null -eq $record.Pid) {
            throw 'Unreadable DNS ownership record. Run Repair-DNS.cmd to inspect.'
        }
        $occupant=Get-Process -Id ([int]$record.Pid) -ErrorAction SilentlyContinue
        if ($null -ne $occupant) {
            throw ('DNS ownership for PID {0} could not be verified. Refusing to kill an unknown process.' -f $record.Pid)
        }
    }
    if (Test-Path -LiteralPath $script:DnsRuntimeFile) {
        Remove-Item -LiteralPath $script:DnsRuntimeFile -Force -ErrorAction Stop
    }
    Remove-Item -LiteralPath $script:DnsReadyFile -Force -ErrorAction SilentlyContinue
    $script:DnsActive=$false
    # Verify rule absence. If this check fails, the normal exit must not proceed.
    if (Get-Command Get-DnsClientNrptRule -ErrorAction SilentlyContinue) {
        $remaining=@(Get-DnsClientNrptRule -ErrorAction Stop | Where-Object {
            $_.DisplayName -ceq $script:DnsRuleLabel -and $_.Comment -ceq 'DiscordOnly local DoH bridge; removed on STOP'
        })
        if ($remaining.Count -gt 0) { throw 'DiscordOnly DNS policy still exists after cleanup.' }
    }
}
function Start-DnsRoute {
    if (!(Get-Command Add-DnsClientNrptRule -ErrorAction SilentlyContinue) -or
        !(Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
        throw 'Windows DNS Client NRPT is not supported on this system.'
    }
    # Clean any orphaned DiscordOnly-only rules from a previous crash.
    Stop-DnsRoute
    $proxyScript=Join-Path $PSScriptRoot 'DiscordDnsProxy.ps1'
    $source=Join-Path $PSScriptRoot 'DiscordDnsProxy.cs'
    if (!(Test-Path -LiteralPath $proxyScript) -or !(Test-Path -LiteralPath $source)) {
        throw 'DNS proxy files are missing. Extract the full ZIP again.'
    }
    $exe=Join-Path $PSHOME 'powershell.exe'
    $arg='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$proxyScript+'" -StateRoot "'+$script:StateRoot+'"'
    $p=Start-Process -FilePath $exe -ArgumentList $arg -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -ErrorAction Stop
    Save-Json $script:DnsRuntimeFile @{Pid=$p.Id;StartUtc=$p.StartTime.ToUniversalTime().ToString('o');ProxyScript=$proxyScript}
    $ready=$false
    for ($i=0;$i -lt 45;$i++) {
        Start-Sleep -Milliseconds 200
        if (Test-Path -LiteralPath $script:DnsReadyFile) { $ready=$true; break }
        $p.Refresh()
        if ($p.HasExited) { break }
    }
    if (!$ready) { throw ('Local encrypted DNS proxy could not listen on 127.0.0.1:53; check '+(Join-Path $script:StateRoot 'dns-proxy.log')) }
    Log 'Encrypted DNS proxy started on 127.0.0.1:53.'
    # Always validate DoH upstream before redirecting the Windows resolver.
    try {
        $records=@(Resolve-DnsName -Server 127.0.0.1 -Name 'discord.com' -DnsOnly -Type A -ErrorAction Stop |
            Where-Object {$_.Type -eq 'A' -and $_.IPAddress} | ForEach-Object {$_.IPAddress})
        if ($records.Count -eq 0 -or (Test-DnsBlocked $records)) {
            throw ('DNS proxy returned an invalid/blocked response: '+($records -join ', '))
        }
        Log ('Encrypted DNS smoke test: discord.com => '+($records -join ', '))
    } catch { throw ('Encrypted DNS is unreachable. Nothing was applied to Windows DNS: '+$_.Exception.Message) }
    $namespaces=@()
    foreach ($domain in $script:DnsDomains) { $namespaces += $domain; $namespaces += ('.'+$domain) }
    # One temporary scoped policy. Keep the original DNS configuration untouched.
    Add-DnsClientNrptRule -Namespace $namespaces -NameServers @('127.0.0.1') `
        -DisplayName $script:DnsRuleLabel -Comment 'DiscordOnly local DoH bridge; removed on STOP' `
        -ErrorAction Stop | Out-Null
    $script:DnsActive=$true
    Clear-DnsCacheSafe
    Log 'Discord-only NRPT active (no adapter-wide DNS change).'
    $addresses=@(Get-DnsResults 'discord.com')
    if ($addresses.Count -eq 0 -or (Test-DnsBlocked $addresses)) {
        throw 'Windows DNS remains unavailable/poisoned despite our scoped policy. Reverting DNS changes.'
    }
    Log ('Windows resolved discord.com => '+($addresses -join ', '))
}
function Process-Conflicts {
    $owned = Owned-Process
    $ours = if ($null -ne $owned) { $owned.Id } else { -1 }
    $candidates = @('winws.exe', 'goodbyedpi.exe', 'byedpi.exe', 'spoofdpi.exe', 'ciadpi.exe')
    $found = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        ($candidates -contains [string]$_.Name.ToLowerInvariant()) -and ([int]$_.ProcessId -ne $ours)
    })
    return $found
}
function Stop-Conflicts {
    $others = @(Process-Conflicts)
    if ($others.Count -eq 0) { return $true }
    $names = ($others | ForEach-Object { '{0} (PID {1})' -f $_.Name, $_.ProcessId }) -join "`r`n"
    if ($true) { # Explicit consent is mandatory, regardless of persisted settings.
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "DPI araclari cakisma yaratabilir:`r`n$names`r`n`r`nYalnizca bu surecler kapatilsin mi?",
            'DiscordOnly - conflict detection', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $script:ConflictDeclined=$true; Log 'Conflicting processes left unchanged by the user.'; return $false }
    }
    foreach ($proc in $others) {
        try {
            # Re-check executable name to avoid PID recycling before stopping a process.
            $current = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$proc.ProcessId) -ErrorAction SilentlyContinue
            if ($null -ne $current -and $current.Name -ieq $proc.Name -and $current.CreationDate -eq $proc.CreationDate) {
                Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop
                Log ('Stopped conflicting tool: {0}, PID {1}' -f $proc.Name, $proc.ProcessId)
            }
        } catch { Log ('Could not stop {0}: {1}' -f $proc.Name, $_.Exception.Message); return $false }
    }
    return $true
}
function Engine-Available {
    foreach ($f in @('winws.exe', 'WinDivert.dll', 'WinDivert64.sys', 'cygwin1.dll', 'ACTIVE_DISCORD_UDP.bin', 'tls_clienthello_www_google_com.bin', 'tls_clienthello_4pda_to.bin')) {
        if (!(Test-Path -LiteralPath (Join-Path $script:Bin $f))) { return $false }
    }
    return $true
}
function Install-Engine([string]$OfflineZip = '') {
    if (Engine-Available) { Log 'Winws engine is ready.'; return $true }
    $bundled = Join-Path (Split-Path -Parent $PSScriptRoot) 'engine\bin'
    if (Test-Path -LiteralPath (Join-Path $bundled 'winws.exe')) {
        [void][System.IO.Directory]::CreateDirectory($script:Bin)
        foreach ($f in @(Get-ChildItem -LiteralPath $bundled -File)) {
            if ($f.Extension -in @('.exe','.dll','.sys','.bin')) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $script:Bin $f.Name) -Force
            }
        }
        if (Engine-Available) { Log 'Bundled engine installed from local files.'; return $true }
    }
    $zip = Join-Path $script:StateRoot 'upstream-1.10.4.zip'
    $stage = Join-Path $script:StateRoot 'install-staging'
    try {
        if ($OfflineZip) {
            Copy-Item -LiteralPath $OfflineZip -Destination $zip -Force
            Log 'Checking the selected upstream ZIP...'
        } else {
            Log 'Downloading pinned upstream zapret 1.10.4 (about 1.5 MB)...'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $script:ZipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 35
        }
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne $script:ZipSha256) { throw 'Release ZIP SHA-256 mismatch. Installation rejected.' }
        if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Force -Recurse }
        [void][System.IO.Directory]::CreateDirectory($stage)
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage)
        $exe = @(Get-ChildItem -LiteralPath $stage -Filter winws.exe -File -Recurse | Where-Object { $_.Directory.Name -ieq 'bin' } | Select-Object -First 1)
        if ($exe.Count -ne 1) { throw 'winws.exe was not found in the archive.' }
        [void][System.IO.Directory]::CreateDirectory($script:Bin)
        foreach ($f in (Get-ChildItem -LiteralPath $exe[0].Directory.FullName -File)) {
            # Copy only the required binaries and upstream packet templates.
            if ($f.Extension -in @('.exe', '.dll', '.sys', '.bin')) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $script:Bin $f.Name) -Force
            }
        }
        $license = @(Get-ChildItem -LiteralPath $stage -Filter LICENSE.txt -File -Recurse | Select-Object -First 1)
        if ($license.Count -gt 0) { Copy-Item -LiteralPath $license[0].FullName -Destination (Join-Path $script:EngineRoot 'UPSTREAM_LICENSE.txt') -Force }
        if (!(Engine-Available)) { throw 'Required engine files were missing after extraction.' }
        Log 'Engine ready. Verified release digest matches upstream.'
        return $true
    } catch {
        Log ('Engine installation failed: ' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Engine installation error', 'OK', 'Error') | Out-Null
        return $false
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Engine-Args([string]$Profile, [bool]$Voice) {
    $domains = 'discord.com,discord.gg,discordapp.net,discordapp.com,discord.media,discordcdn.com'
    $tcpPorts = '443,2053,2083,2087,2096,8443'
    $voicePorts = '19294-19344,50000-50100'
    $tcp = @("--wf-tcp=$tcpPorts")
    if ($Voice) { $tcp += "--wf-udp=$voicePorts" }
    $tcp += "--filter-tcp=$tcpPorts"
    $tcp += "--hostlist-domains=$domains"
    $fake = Join-Path $script:Bin 'tls_clienthello_www_google_com.bin'
    $overlap = Join-Path $script:Bin 'tls_clienthello_4pda_to.bin'
    switch ($Profile) {
        'Gentle' {
            $tcp += '--dpi-desync=multidisorder'
            $tcp += '--dpi-desync-split-pos=2'
        }
        'Alternative' {
            $tcp += '--dpi-desync=fake,fakedsplit'
            $tcp += '--dpi-desync-repeats=6'
            $tcp += '--dpi-desync-fooling=ts'
            $tcp += '--dpi-desync-fakedsplit-pattern=0x00'
            $tcp += ('--dpi-desync-fake-tls="' + $fake + '"')
        }
        default {
            $tcp += '--dpi-desync=multisplit'
            $tcp += '--dpi-desync-split-seqovl=568'
            $tcp += '--dpi-desync-split-pos=1'
            $tcp += ('--dpi-desync-split-seqovl-pattern="' + $overlap + '"')
        }
    }
    if ($Voice) {
        $voiceFake = Join-Path $script:Bin 'ACTIVE_DISCORD_UDP.bin'
        $tcp += '--new'
        $tcp += "--filter-udp=$voicePorts"
        $tcp += '--filter-l7=discord,stun'
        $tcp += '--dpi-desync=fake'
        $tcp += ('--dpi-desync-fake-discord="' + $voiceFake + '"')
        $tcp += ('--dpi-desync-fake-stun="' + $voiceFake + '"')
        $tcp += '--dpi-desync-repeats=6'
    }
    return $tcp
}
function Refresh-Status {
    if (!$script:StatusLabel -or $script:StatusLabel.IsDisposed) { return }
    $p = Owned-Process
    $isRunning = $null -ne $p
    $trialActive = ($null -ne $script:AutoTrial -and $script:AutoTrial.Active)
    if ($trialActive -and $isRunning) {
        if ($script:AutoTrial.ClientSeen) {
            $seconds=[math]::Max(0,[math]::Ceiling(($script:AutoTrial.Deadline-[DateTime]::UtcNow).TotalSeconds))
            $script:StatusLabel.Text=('CHECKING {0} HTTPS  |  {1}s  |  PID {2}' -f $script:ProfileBox.SelectedItem,$seconds,$p.Id)
        } else {
            $script:StatusLabel.Text=('CHECKING {0} HTTPS  |  awaiting Discord launch  |  PID {1}' -f $script:ProfileBox.SelectedItem,$p.Id)
        }
        $script:StatusLabel.ForeColor=[System.Drawing.Color]::FromArgb(245, 191, 87)
    } else {
        $script:StatusLabel.Text = if ($isRunning) { "RUNNING  |  PID $($p.Id)" } else { 'STOPPED' }
        $script:StatusLabel.ForeColor = if ($isRunning) { [System.Drawing.Color]::FromArgb(68, 209, 142) } else { [System.Drawing.Color]::FromArgb(255, 171, 100) }
    }
    $script:StartButton.Enabled = (!$isRunning -and !$trialActive)
    $script:StopButton.Enabled = ($isRunning -or $trialActive)
    $script:RestartButton.Enabled = ($isRunning -and !$trialActive)
    if ($script:ProfileBox) { $script:ProfileBox.Enabled = !$trialActive }
    if ($script:Tray) { $script:Tray.Text = if ($isRunning) { 'DiscordOnly - running' } else { 'DiscordOnly - stopped' } }
    if ($script:LastKnownRunning -and !$isRunning) {
        Log 'Winws is no longer running.'
        if ($script:DnsActive) {
            try { Stop-DnsRoute; Log 'DNS policy cleaned up after engine unexpectedly stopped.' }
            catch { Log ('Automatic DNS cleanup failed: '+$_.Exception.Message) }
        }
    }
    $script:LastKnownRunning = $isRunning
}
function Start-Bypass([bool]$AutoLaunch = $true, [bool]$QuietErrors = $false) {
    $startedEngine=$null
    try {
        if ($null -ne (Owned-Process)) { Log 'Already running.'; return }
        if (!(Engine-Available)) { if (!(Install-Engine)) { return } }
        if (!(Stop-Conflicts)) { return }
        Start-DnsRoute
        $args = @(Engine-Args ([string]$script:ProfileBox.SelectedItem) ([bool]$script:VoiceCheck.Checked))
        $exe = Join-Path $script:Bin 'winws.exe'
        $p = Start-Process -FilePath $exe -ArgumentList ($args -join ' ') -WorkingDirectory $script:Bin -WindowStyle Hidden -PassThru -ErrorAction Stop
        $startedEngine=$p
        Save-Json $script:RuntimeFile @{ Pid = $p.Id; StartUtc = $p.StartTime.ToUniversalTime().ToString('o') }
        Start-Sleep -Milliseconds 750
        $p.Refresh()
        if ($p.HasExited) { throw ('winws exited immediately with code {0}. Check conflicting drivers / profile.' -f $p.ExitCode) }
        Log ('Started with profile {0}; voice={1}; PID={2}' -f $script:ProfileBox.SelectedItem, $script:VoiceCheck.Checked, $p.Id)
        Refresh-Status
        if ($AutoLaunch) {
            # Never stop existing Discord instances as a side effect of START.
            # Launch after DNS policy and verified live DPI engine are ready.
            Log 'START succeeded; opening Discord automatically.'
            [void](Start-Discord)
        }
    } catch {
        Log ('Start failed: ' + $_.Exception.Message)
        # Use the just-created Process handle even if writing owned.json failed:
        # an unrecorded winws must not be left in the background.
        if ($null -ne $startedEngine) {
            try {
                $startedEngine.Refresh()
                if (!$startedEngine.HasExited) {
                    $startedEngine.Kill()
                    [void]$startedEngine.WaitForExit(3000)
                }
            } catch { Log ('Unrecorded DPI engine rollback FAILED: '+$_.Exception.Message) }
        }
        try { [void](Stop-Bypass) } catch { Log ('Automatic rollback failed: '+$_.Exception.Message) }
        if (!$QuietErrors) { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Start error', 'OK', 'Error') | Out-Null }
    }
}
function Stop-Bypass {
    # Always attempt BOTH cleanup stages, even if one fails.
    # Return $false rather than pretending exit is safe after a partial failure.
    $problems = New-Object 'System.Collections.Generic.List[string]'
    $p = Owned-Process
    if ($null -ne $p) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            [void]$p.WaitForExit(3000)
            $p.Refresh()
            if (!$p.HasExited) { throw ('winws PID {0} did not exit.' -f $p.Id) }
            Log ('Stopped own winws PID {0}' -f $p.Id)
            if (Test-Path -LiteralPath $script:RuntimeFile) {
                Remove-Item -LiteralPath $script:RuntimeFile -Force -ErrorAction Stop
            }
        } catch {
            $problems.Add('DPI engine: '+$_.Exception.Message)
            Log ('Could not stop own winws: '+$_.Exception.Message)
        }
    } elseif (Test-Path -LiteralPath $script:RuntimeFile) {
        $record=Load-Json $script:RuntimeFile
        if ($null -eq $record -or $null -eq $record.Pid) {
            $problems.Add('DPI engine ownership record is unreadable.')
        } else {
            $occupant=Get-Process -Id ([int]$record.Pid) -ErrorAction SilentlyContinue
            if ($null -ne $occupant) {
                $problems.Add(('DPI engine PID {0} cannot be verified; refusing to kill another process.' -f $record.Pid))
            } else {
                try {
                    Remove-Item -LiteralPath $script:RuntimeFile -Force -ErrorAction Stop
                    Log 'Removed stale DPI ownership record (process already exited).'
                } catch { $problems.Add('Could not clear stale DPI metadata: '+$_.Exception.Message) }
            }
        }
    }
    try { Stop-DnsRoute }
    catch {
        $problems.Add('Scoped DNS: '+$_.Exception.Message)
        Log ('DNS cleanup failed; owner record preserved if still active: '+$_.Exception.Message)
    }
    if ($null -ne (Owned-Process)) { $problems.Add('DPI engine still runs.') }
    if ($null -ne (Owned-DnsProcess)) { $problems.Add('DNS proxy still runs.') }
    Refresh-Status
    if ($problems.Count -gt 0) {
        Log ('CLEANUP INCOMPLETE: '+($problems -join ' | '))
        return $false
    }
    Log 'CLEANUP VERIFIED: own DPI process stopped, own DNS proxy stopped, scoped NRPT removed.'
    return $true
}
function Save-Settings {
    Save-Json $script:SettingsFile @{
        Profile = [string]$script:ProfileBox.SelectedItem
        Voice = [bool]$script:VoiceCheck.Checked
        AutoConflicts = [bool]$script:AutoConflicts.Checked
    }
}
function Discord-Executable {
    $local = $env:LOCALAPPDATA
    $updater = Join-Path $local 'Discord\Update.exe'
    if (Test-Path $updater) { return @{Exe=$updater; Args='--processStart Discord.exe'} }
    $folder = Join-Path $local 'Discord'
    if (Test-Path $folder) {
        $apps = @(Get-ChildItem -LiteralPath $folder -Directory -Filter 'app-*' | Sort-Object Name -Descending)
        foreach ($app in $apps) { $exe=Join-Path $app.FullName 'Discord.exe'; if (Test-Path $exe) { return @{Exe=$exe;Args=''} } }
    }
    return $null
}
# Discord is independent of the bypass lifecycle. Only the manual Discord
# Close/Restart buttons may stop it; STOP and tray Exit never do.
function Discord-Running {
    return ($null -ne (Get-Process -Name Discord -ErrorAction SilentlyContinue | Select-Object -First 1))
}
function Start-Discord {
    try {
        if (Discord-Running) {
            Log 'Discord is already running; keeping the existing client open.'
            return $true
        }
        $found = Discord-Executable
        if ($null -eq $found) {
            throw 'Discord stable was not found in LocalAppData. Check your Discord installation.'
        }
        $workingDir = Split-Path -Parent ([string]$found.Exe)
        if ($found.Args) {
            Start-Process -FilePath $found.Exe -ArgumentList $found.Args -WorkingDirectory $workingDir -ErrorAction Stop | Out-Null
            Log 'Discord updater launch requested.'
        } else {
            Start-Process -FilePath $found.Exe -WorkingDirectory $workingDir -ErrorAction Stop | Out-Null
            Log 'Discord executable launch requested.'
        }
        # Update.exe may exit before the actual Discord.exe instance is created.
        # Do not claim success solely because Start-Process did not throw.
        for ($i = 0; $i -lt 12; $i++) {
            Start-Sleep -Milliseconds 250
            if (Discord-Running) {
                Log 'Discord process detected after automatic launch.'
                return $true
            }
        }
        # If the updater is unavailable/stuck, use the installed version directly.
        # Discord itself is never terminated by this fallback.
        if ($found.Args) {
            $folder = Join-Path $env:LOCALAPPDATA 'Discord'
            if (Test-Path -LiteralPath $folder) {
                $apps = @(Get-ChildItem -LiteralPath $folder -Directory -Filter 'app-*' | Sort-Object Name -Descending)
                foreach ($app in $apps) {
                    $direct = Join-Path $app.FullName 'Discord.exe'
                    if (Test-Path -LiteralPath $direct) {
                        Start-Process -FilePath $direct -WorkingDirectory $app.FullName -ErrorAction Stop | Out-Null
                        Log 'Discord updater did not spawn a client promptly; attempted installed executable fallback.'
                        break
                    }
                }
            }
        }
        # An update can continue in the background; explain the difference.
        if (Discord-Running) {
            Log 'Discord process detected after fallback.'
            return $true
        }
        Log 'Discord launch command sent but Discord.exe was not observed yet. It may still be updating; use the Open Discord button or check the installation.'
        return $false
    } catch {
        Log ('Discord auto-launch failed: ' + $_.Exception.Message)
        return $false
    }
}
function Stop-Discord {
    $items = @(Get-Process -Name Discord -ErrorAction SilentlyContinue)
    foreach ($p in $items) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop }
        catch { Log ('Discord PID {0} could not be stopped: {1}' -f $p.Id, $_.Exception.Message) }
    }
    Log ('Stopped Discord processes: {0}' -f $items.Count)
}
function Get-DnsResults([string]$Domain) {
    try {
        return @([Net.Dns]::GetHostAddresses($Domain) | ForEach-Object { $_.IPAddressToString })
    } catch {
        Log ('DNS lookup failed for ' + $Domain + ': ' + $_.Exception.Message)
        return @()
    }
}
function Test-DnsBlocked([string[]]$Addresses) {
    # OONI's independently documented Turkish block response. Do not infer
    # every unknown/private IP is a block; report them for human inspection.
    return ($Addresses -contains '195.175.254.2')
}
function Test-CloudflareDoh([string]$Domain) {
    # Diagnostic ONLY: this response is not installed into Windows DNS cache,
    # a hosts file, or the Discord process. Never advertise it as a fix.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $url = 'https://cloudflare-dns.com/dns-query?name=' + [Uri]::EscapeDataString($Domain) + '&type=A'
        $result = Invoke-RestMethod -Uri $url -Headers @{ Accept='application/dns-json' } -Method Get -TimeoutSec 5 -ErrorAction Stop
        $ips = @($result.Answer | Where-Object { $_.type -eq 1 -and $_.data -match '^\d{1,3}(\.\d{1,3}){3}$' } | ForEach-Object { [string]$_.data })
        if ($ips.Count -gt 0) {
            Log ('Encrypted DoH comparison: ' + $Domain + ' => ' + ($ips -join ', '))
        } else { Log ('Encrypted DoH comparison returned no A records for ' + $Domain) }
    } catch {
        Log ('Encrypted DoH comparison unavailable (not proof of blocking): ' + $_.Exception.Message)
    }
}
function Show-DnsHelp {
    $msg=@'
Press START:
1. Start a local DNS-to-HTTPS server on 127.0.0.1:53.
2. Install temporary Windows NRPT rules ONLY for Discord domain names.
3. Verify DNS is not redirected to the ISP block address.
4. Start the scoped DPI engine and restart Discord automatically.

Press STOP (or exit from tray):
- Remove ONLY DiscordOnly-owned DNS policies and stop our DNS process.
- Never modify your adapter DNS servers, hosts file, VPN, or default gateway.

If a crash leaves a DNS policy, run Repair-DNS.cmd as administrator.
Port 53 may already be in use on PCs with other local DNS tools.
Network, Windows policy, and HTTPS blocks differ; no universal success guarantee.
'@
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'DiscordOnly - DNS behavior', 'OK', 'Information')
}
function Test-DiscordConnection {
    Log '--- Discord-only DNS + HTTPS diagnostic (read-only) ---'
    $owned = Owned-Process
    if ($null -eq $owned) {
        Log 'DPI engine is STOPPED. If your ISP blocks TLS, press START before testing.'
    } else { Log ('DPI engine is RUNNING, PID ' + $owned.Id) }

    $domains = @('discord.com', 'updates.discord.com')
    $blocked = $false
    foreach ($domain in $domains) {
        $ips = @(Get-DnsResults $domain)
        if ($ips.Count -gt 0) { Log ('System DNS: ' + $domain + ' => ' + ($ips -join ', ')) }
        if (Test-DnsBlocked $ips) { $blocked = $true; Log ('BLOCKED DNS RESULT: ' + $domain + ' returned censorship IP 195.175.254.2.') }
    }
    if ($blocked) {
        Log 'DIAGNOSIS: DNS poisoning detected. Press START to activate the temporary Discord-only DoH resolver.'
        Test-CloudflareDoh 'discord.com'
        Log 'If START has already been used, the scoped resolver may be unsupported or another DNS policy is overriding it.'
        Log 'NOTE: This test does not validate voice; test a real Discord voice channel separately.'
        return
    }
    try {
        $request = [Net.HttpWebRequest]::Create('https://discord.com/api/v10/gateway')
        $request.Timeout = 5000
        $request.ReadWriteTimeout = 5000
        $response = $request.GetResponse()
        try { Log ('Discord gateway HTTPS: HTTP {0} (reachability confirmed, voice NOT tested)' -f [int]$response.StatusCode) }
        finally { $response.Close() }
    } catch {
        Log ('HTTPS request failed (potential TLS/DPI, routing or server issue): ' + $_.Exception.Message)
        Log 'If DNS is correct but HTTPS fails, start the engine and switch DPI profile.'
    }
    Log 'NOTE: This test does not validate voice; test a real Discord voice channel separately.'
}
# START watchdog checks Discord HTTPS independently from GUI paint/update timing.
# A reachable gateway is sufficient to retain the selected profile. Window
# availability is NOT used as a negative signal (Updater may take longer).
# Before any automatic switch we must observe a Discord.exe process and a
# full 10-second unsuccessful HTTPS window with an alive local DNS resolver.
# If startup itself fails, preserve the current strategy and ask for diagnosis.
function Abort-TrialProbe {
    if ($null -eq $script:AutoTrial) { return }
    if ($null -ne $script:AutoTrial.Request) {
        try { $script:AutoTrial.Request.Abort() } catch { }
    }
    $script:AutoTrial.Request=$null
    $script:AutoTrial.AsyncResult=$null
}
function Begin-TrialProbe {
    $trial=$script:AutoTrial
    if ($null -eq $trial -or !$trial.Active -or $trial.GatewayOK -or $null -ne $trial.Request) { return }
    try {
        $req=[Net.HttpWebRequest]::Create('https://discord.com/api/v10/gateway')
        $req.Method='GET'
        $req.Timeout=3500
        $req.ReadWriteTimeout=3500
        $req.AllowAutoRedirect=$false
        $trial.AsyncResult=$req.BeginGetResponse($null, $null)
        $trial.Request=$req
        $trial.ProbeStarted=[DateTime]::UtcNow
    } catch {
        Log ('AUTO CONNECT: could not start asynchronous HTTPS probe: '+$_.Exception.Message)
        $trial.NextProbe=[DateTime]::UtcNow.AddSeconds(2)
    }
}
function Poll-TrialProbe {
    $trial=$script:AutoTrial
    if ($null -eq $trial -or !$trial.Active -or $trial.GatewayOK) { return }
    if ($null -eq $trial.Request) {
        if ([DateTime]::UtcNow -ge $trial.NextProbe) { Begin-TrialProbe }
        return
    }
    if ($null -ne $trial.AsyncResult -and $trial.AsyncResult.IsCompleted) {
        try {
            $response=$trial.Request.EndGetResponse($trial.AsyncResult)
            try {
                $code=[int]$response.StatusCode
                if ($code -ge 200 -and $code -lt 400) { $trial.GatewayOK=$true }
                else { Log ('AUTO CONNECT: gateway HTTP '+$code) }
            } finally { $response.Close() }
        } catch { Log ('AUTO CONNECT: HTTPS probe failed: '+$_.Exception.Message) }
        $trial.Request=$null
        $trial.AsyncResult=$null
        $trial.NextProbe=[DateTime]::UtcNow.AddSeconds(2)
        return
    }
    if (([DateTime]::UtcNow-$trial.ProbeStarted).TotalMilliseconds -ge 3500) {
        Abort-TrialProbe
        $trial.NextProbe=[DateTime]::UtcNow.AddMilliseconds(500)
        Log 'AUTO CONNECT: HTTPS probe timed out; retrying within this profile window.'
    }
}
function Cancel-AutoTrial([string]$Reason = '') {
    if ($null -eq $script:AutoTrial -or !$script:AutoTrial.Active) { return }
    Abort-TrialProbe
    $original=[string]$script:AutoTrial.Original
    $script:AutoTrial.Active=$false
    if ($script:TrialTimer) { $script:TrialTimer.Stop() }
    # Do not mislabel an ACTIVE alternative engine as Balanced if safe teardown
    # failed. Only restore the drop-down if no managed engine is left running.
    if ($null -eq (Owned-Process)) {
        $script:ChangingProfileAutomatically=$true
        try { $script:ProfileBox.SelectedItem=$original }
        finally { $script:ChangingProfileAutomatically=$false }
        if ($Reason) { Log ('AUTO CONNECT: cancelled - '+$Reason+'; saved profile selection restored.') }
    } else {
        if ($Reason) { Log ('AUTO CONNECT: cancelled - '+$Reason+'; current engine/profile kept until safe STOP.') }
    }
    Refresh-Status
}
function Hold-AutoTrial([string]$Reason) {
    # A timeout during Discord startup is NOT proof of a bad DPI strategy.
    # Keep the owned DNS + DPI engine intact so a slow updater can finish.
    if ($null -eq $script:AutoTrial -or !$script:AutoTrial.Active) { return }
    Abort-TrialProbe
    $script:AutoTrial.Active=$false
    if ($script:TrialTimer) { $script:TrialTimer.Stop() }
    Log ('AUTO CONNECT: keeping current profile without switching: '+$Reason)
    Log 'AUTO CONNECT: Open Discord manually if needed; use DNS + HTTPS Test or AUTO PROFILE to investigate.'
    Refresh-Status
}
function Finish-AutoTrial([bool]$Success) {
    if ($null -eq $script:AutoTrial) { return }
    $trial=$script:AutoTrial
    Abort-TrialProbe
    $trial.Active=$false
    if ($script:TrialTimer) { $script:TrialTimer.Stop() }
    if ($Success) {
        $profile=[string]$script:ProfileBox.SelectedItem
        Log ('AUTO CONNECT: gateway HTTPS is reachable with {0}. Profile retained; Discord login/voice is not verified.' -f $profile)
        Save-Settings
    } else {
        # Never leave the *last* failed candidate selected after all retries.
        # Restore the user's original strategy instead of shutting down all DNS/DPI.
        $original=[string]$trial.Original
        Log ('AUTO CONNECT: gateway unavailable with each tried profile; attempting to restore {0}.' -f $original)
        if ([string]$script:ProfileBox.SelectedItem -ne $original) {
            if (!(Stop-Bypass)) {
                Log 'AUTO CONNECT: cannot restore original engine because cleanup failed. Current engine left untouched for manual recovery.'
                Refresh-Status
                return
            }
            $script:ChangingProfileAutomatically=$true
            try { $script:ProfileBox.SelectedItem=$original }
            finally { $script:ChangingProfileAutomatically=$false }
            Start-Bypass -AutoLaunch $true -QuietErrors $true
        }
        if ($null -ne (Owned-Process)) {
            Save-Settings
            Log 'AUTO CONNECT: original profile is running again. Discord remains open; connectivity still needs manual verification.'
        } else {
            Log 'AUTO CONNECT: original engine could not be restarted. Use Start-Debug.cmd and EVENT LOG for diagnosis.'
        }
    }
    Refresh-Status
}
function Start-TrialProfile {
    $trial=$script:AutoTrial
    if ($null -eq $trial -or !$trial.Active) { return }
    $profile=[string]$trial.Order[$trial.Index]
    $script:ChangingProfileAutomatically=$true
    try { $script:ProfileBox.SelectedItem=$profile }
    finally { $script:ChangingProfileAutomatically=$false }
    Log ('AUTO CONNECT: trying {0} (profile {1}/{2}; HTTPS success locks profile immediately).' -f $profile, ($trial.Index+1), $trial.Order.Count)
    # A trial never kills/restarts an already running Discord client. Only our
    # verified owned winws/DNS workers are stopped between trials.
    Start-Bypass -AutoLaunch $true -QuietErrors $true
    if ($null -eq (Owned-Process)) {
        if ($script:ConflictDeclined) {
            Cancel-AutoTrial 'user declined closing an incompatible DPI tool'
            return
        }
        Log ('AUTO CONNECT: {0} could not start; attempting next profile.' -f $profile)
        Next-TrialProfile 'engine startup failed'
        return
    }
    $trial.GatewayOK=$false
    $trial.Request=$null
    $trial.AsyncResult=$null
    $trial.ProbeStarted=[DateTime]::MinValue
    $trial.NextProbe=[DateTime]::UtcNow
    # Keep the original strategy while Discord is still launching/updating.
    # A responsive *window* must never be required for a working HTTPS strategy.
    $trial.ClientSeen=[bool](Discord-Running)
    $trial.LaunchDeadline=[DateTime]::UtcNow.AddSeconds(20)
    $trial.Deadline=[DateTime]::MaxValue
    if ($trial.ClientSeen) {
        $trial.Deadline=[DateTime]::UtcNow.AddSeconds(10)
        Log 'AUTO CONNECT: Discord.exe detected; beginning 10-second HTTPS fallback window.'
    } else {
        Log 'AUTO CONNECT: waiting for Discord.exe; will NOT switch based on a slow updater.'
    }
    Begin-TrialProbe
    Refresh-Status
}
function Next-TrialProfile([string]$Reason) {
    $trial=$script:AutoTrial
    if ($null -eq $trial -or !$trial.Active) { return }
    Abort-TrialProbe
    $profile=[string]$trial.Order[$trial.Index]
    Log ('AUTO CONNECT: {0} not confirmed ({1}); switching safely.' -f $profile,$Reason)
    if (!(Stop-Bypass)) {
        Cancel-AutoTrial 'previous profile cleanup failed; refusing to overlap engines or DNS routes.'
        return
    }
    $trial.Index++
    if ($trial.Index -ge $trial.Order.Count) { Finish-AutoTrial $false; return }
    Start-TrialProfile
}
function Monitor-AutoTrial {
    $trial=$script:AutoTrial
    if ($null -eq $trial -or !$trial.Active) { return }
    if ($null -eq (Owned-Process)) {
        # An actual winws exit is a confirmed engine failure, not a slow UI.
        Next-TrialProfile 'winws process exited'
        return
    }
    Poll-TrialProbe
    if ($trial.GatewayOK) {
        # CRITICAL: success is gateway HTTPS, never gateway HTTPS AND a visible
        # Discord window. The latter caused the v0.3.3 premature rotation.
        Finish-AutoTrial $true
        return
    }
    $now=[DateTime]::UtcNow
    if (!$trial.ClientSeen) {
        if (Discord-Running) {
            $trial.ClientSeen=$true
            $trial.Deadline=$now.AddSeconds(10)
            Log 'AUTO CONNECT: Discord.exe appeared; counting 10 seconds of HTTPS failures before any profile switch.'
        } elseif ($now -ge $trial.LaunchDeadline) {
            Hold-AutoTrial 'Discord.exe did not start within 20 seconds. This is not evidence the selected DPI profile failed.'
            return
        }
    }
    Refresh-Status
    if ($trial.ClientSeen -and $now -ge $trial.Deadline) {
        if ($null -eq (Owned-DnsProcess)) {
            Hold-AutoTrial 'local DNS proxy is not running; switching DPI profiles cannot repair the DNS worker.'
            return
        }
        Next-TrialProfile 'Discord.exe observed; gateway HTTPS still failed during 10 seconds'
    }
}
function Start-AutoConnection {
    if ($null -ne $script:AutoTrial -and $script:AutoTrial.Active) {
        Log 'AUTO CONNECT: a profile trial is already in progress.'
        return
    }
    if ($null -ne (Owned-Process)) {
        Log 'DPI engine already runs. Use RESTART to recheck profiles.'
        return
    }
    $original=[string]$script:ProfileBox.SelectedItem
    $order=@($original)
    foreach ($candidate in @('Balanced','Alternative','Gentle')) {
        if ($candidate -ne $original) { $order+= $candidate }
    }
    $script:ConflictDeclined=$false
    $script:AutoTrial=@{
        Active=$true; Order=$order; Index=0; Original=$original
        Deadline=[DateTime]::MaxValue; GatewayOK=$false
        LaunchDeadline=[DateTime]::MaxValue; ClientSeen=$false
        Request=$null; AsyncResult=$null; ProbeStarted=[DateTime]::MinValue
        NextProbe=[DateTime]::UtcNow
    }
    Log 'AUTO CONNECT: gateway HTTPS success keeps the profile immediately. Fallback requires confirmed failure after Discord.exe starts.'
    Start-TrialProfile
    if ($script:AutoTrial.Active -and $script:TrialTimer) { $script:TrialTimer.Start() }
}
# Explicit, user-initiated discovery; never automatically rotate a profile that is
# already serving a working Discord connection. HTTPS does NOT validate voice UDP.
function Test-GatewayQuick {
    try {
        $request=[Net.HttpWebRequest]::Create('https://discord.com/api/v10/gateway')
        $request.Timeout=4500
        $request.ReadWriteTimeout=4500
        $response=$request.GetResponse()
        try { return ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) }
        finally { $response.Close() }
    } catch {
        Log ('Gateway probe did not succeed: '+$_.Exception.Message)
        return $false
    }
}
function Find-WorkingProfile {
    if ($null -ne $script:AutoTrial -and $script:AutoTrial.Active) {
        Log 'AUTO PROFILE: wait for automatic startup trials to finish or press STOP.'
        return
    }
    $confirm=[System.Windows.Forms.MessageBox]::Show(
        "This checks Discord HTTPS and may briefly restart the DPI engine.`r`n" +
        "It cannot prove voice chat works.`r`n`r`n" +
        "Keep the working profile if HTTPS already succeeds?",
        'DiscordOnly - Auto profile', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $original=[string]$script:ProfileBox.SelectedItem
    $wasRunning=($null -ne (Owned-Process))
    $working=$false
    $attempted=@()
    $order=@($original)
    foreach ($candidate in @('Balanced','Alternative','Gentle')) {
        if ($candidate -ne $original) { $order += $candidate }
    }
    try {
        foreach ($profile in $order) {
            $attempted+= $profile
            Log ('AUTO PROFILE: Trying {0} ({1}/{2})' -f $profile,$attempted.Count,$order.Count)
            if (([string]$script:ProfileBox.SelectedItem -ne $profile) -or
                ($null -eq (Owned-Process))) {
                if ($null -ne (Owned-Process)) { if (!(Stop-Bypass)) { throw 'AUTO PROFILE: cleanup failed; cannot switch strategy.' } }
                $script:ProfileBox.SelectedItem=$profile
                Start-Bypass -AutoLaunch $false
            }
            if ($null -eq (Owned-Process)) {
                Log ('AUTO PROFILE: Engine could not start with {0}. Stopping.' -f $profile)
                break
            }
            # Give Windows/WinDivert a moment after a profile transition.
            Start-Sleep -Milliseconds 500
            if (Test-GatewayQuick) {
                $working=$true
                Log ('AUTO PROFILE: HTTPS reachable on {0}; profile saved.' -f $profile)
                if (!$wasRunning -or $profile -ne $original) {
                    [void](Start-Discord)
                } else {
                    Log 'AUTO PROFILE: Kept the working engine and existing Discord session untouched.'
                }
                break
            }
        }
    } catch { Log ('AUTO PROFILE error: '+$_.Exception.Message) }
    if (!$working) {
        Log 'AUTO PROFILE: No HTTPS-confirmed profile. Restoring the previous choice.'
        try {
            if ($null -ne (Owned-Process)) { if (!(Stop-Bypass)) { throw 'Cannot restore prior profile; old process did not stop cleanly.' } }
            $script:ProfileBox.SelectedItem=$original
            if ($wasRunning) { Start-Bypass -AutoLaunch $false }
        } catch { Log ('Could not restore original profile: '+$_.Exception.Message) }
        [void][System.Windows.Forms.MessageBox]::Show(
            'No profile passed the HTTPS test. Previous setting restored. Check app.log and try a real Discord voice test separately.',
            'DiscordOnly - Auto profile', 'OK', 'Warning')
    } else {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Discord HTTPS is reachable. Test a real voice channel: UDP is not checked by Auto Profile.',
            'DiscordOnly - Auto profile', 'OK', 'Information')
    }
    Refresh-Status
}
function Copy-Diagnostics {
    try {
        $lines=@(Get-Content -LiteralPath $script:LogFile -Tail 120 -ErrorAction Stop)
        [System.Windows.Forms.Clipboard]::SetText(($lines -join [Environment]::NewLine))
        Log 'Copied last 120 log lines to clipboard (may contain local paths and IPs).'
    } catch { Log ('Clipboard copy failed: '+$_.Exception.Message) }
}
function Open-LogFolder {
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"'+$script:StateRoot+'"') -ErrorAction Stop | Out-Null }
    catch { Log ('Could not open log folder: '+$_.Exception.Message) }
}

function Ui-Button([string]$Text, [int]$X, [int]$Y, [int]$Width, [System.Drawing.Color]$Color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text=$Text; $b.Location=[System.Drawing.Point]::new($X,$Y); $b.Size=[System.Drawing.Size]::new($Width,39)
    $b.BackColor=$Color; $b.ForeColor=[System.Drawing.Color]::White; $b.FlatStyle='Flat'
    $b.FlatAppearance.BorderSize=0; $b.Cursor='Hand'; $b.Font=[System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    return $b
}
function Ui-Label([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Size) {
    $l=New-Object System.Windows.Forms.Label
    $l.Text=$Text; $l.Location=[System.Drawing.Point]::new($X,$Y); $l.Size=[System.Drawing.Size]::new($Width,$Height)
    $l.ForeColor=[System.Drawing.Color]::FromArgb(228,232,242)
    $l.Font=[System.Drawing.Font]::new('Segoe UI',$Size)
    return $l
}

# Single-instance guard, keeping the Mutex object alive while the form is open.
$created=$false
$script:InstanceMutex = [System.Threading.Mutex]::new($true, 'Local\DiscordOnly_DPI_Manager_2026', [ref]$created)
if (!$created) { [System.Windows.Forms.MessageBox]::Show('DiscordOnly is already open. Check the system tray.','Already open') | Out-Null; return }
$timer = $null
try {
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = "DiscordOnly - DPI Manager v$script:Version"
    $script:Form.StartPosition='CenterScreen'; $script:Form.Size=[System.Drawing.Size]::new(700,675)
    $script:Form.MinimumSize=[System.Drawing.Size]::new(700,675)
    $script:Form.BackColor=[System.Drawing.Color]::FromArgb(21,24,33)
    $script:Form.ForeColor=[System.Drawing.Color]::White
    $script:Form.Icon=[System.Drawing.SystemIcons]::Shield

    $heading=Ui-Label 'DiscordOnly' 23 14 440 42 22
    $sub=Ui-Label 'Discord-only encrypted DNS + selective DPI / No full-tunnel VPN' 26 55 640 30 9
    $sub.ForeColor=[System.Drawing.Color]::FromArgb(160,173,198)
    $script:StatusLabel=Ui-Label 'STOPPED' 28 92 635 34 14
    $script:Form.Controls.AddRange(@($heading,$sub,$script:StatusLabel))

    $script:StartButton=Ui-Button 'START' 24 137 148 ([System.Drawing.Color]::FromArgb(35,155,101))
    $script:StopButton=Ui-Button 'STOP' 186 137 148 ([System.Drawing.Color]::FromArgb(179,67,75))
    $script:RestartButton=Ui-Button 'RESTART' 348 137 148 ([System.Drawing.Color]::FromArgb(65,103,184))
    $installBtn=Ui-Button 'ENGINE SETUP' 510 137 153 ([System.Drawing.Color]::FromArgb(70,74,88))
    $script:Form.Controls.AddRange(@($script:StartButton,$script:StopButton,$script:RestartButton,$installBtn))

    $profileLbl=Ui-Label 'DPI strategy' 26 199 150 23 10
    $script:ProfileBox=New-Object System.Windows.Forms.ComboBox
    $script:ProfileBox.Location=[System.Drawing.Point]::new(166,196)
    $script:ProfileBox.Size=[System.Drawing.Size]::new(215,30)
    $script:ProfileBox.DropDownStyle='DropDownList'
    $script:ProfileBox.Items.AddRange(@('Balanced','Alternative','Gentle'))
    $script:ProfileBox.SelectedIndex=0
    $script:ProfileBox.BackColor=[System.Drawing.Color]::FromArgb(39,43,56)
    $script:ProfileBox.ForeColor=[System.Drawing.Color]::White
    $script:VoiceCheck=New-Object System.Windows.Forms.CheckBox
    $script:VoiceCheck.Location=[System.Drawing.Point]::new(400,198)
    $script:VoiceCheck.Size=[System.Drawing.Size]::new(260,28)
    $script:VoiceCheck.Text='Enable Discord voice (UDP)'; $script:VoiceCheck.Checked=$true
    $script:AutoConflicts=New-Object System.Windows.Forms.CheckBox
    $script:AutoConflicts.Location=[System.Drawing.Point]::new(28,239)
    $script:AutoConflicts.Size=[System.Drawing.Size]::new(600,25)
    $script:AutoConflicts.Text='Security: confirm before stopping conflicting DPI tools'
    $script:AutoConflicts.Checked=$false
    $script:AutoConflicts.Enabled=$false # Safety: do not auto-terminate unrelated processes.
    $script:AutoOpenDiscord=New-Object System.Windows.Forms.CheckBox
    $script:AutoOpenDiscord.Location=[System.Drawing.Point]::new(28,267)
    $script:AutoOpenDiscord.Size=[System.Drawing.Size]::new(610,26)
    $script:AutoOpenDiscord.Text='Auto-open Discord; safe HTTPS fallback if needed'
    $script:AutoOpenDiscord.Checked=$true
    $script:AutoOpenDiscord.Enabled=$false
    $script:Form.Controls.AddRange(@($profileLbl,$script:ProfileBox,$script:VoiceCheck,$script:AutoConflicts,$script:AutoOpenDiscord))

    $discordLbl=Ui-Label 'DISCORD DESKTOP' 25 308 450 24 10
    $discordOpen=Ui-Button 'Open Discord' 24 340 146 ([System.Drawing.Color]::FromArgb(70,74,88))
    $discordClose=Ui-Button 'Close Discord' 184 340 146 ([System.Drawing.Color]::FromArgb(70,74,88))
    $discordRestart=Ui-Button 'Restart Discord' 344 340 150 ([System.Drawing.Color]::FromArgb(70,74,88))
    $diagnostic=Ui-Button 'DNS + HTTPS Test' 509 340 154 ([System.Drawing.Color]::FromArgb(70,74,88))
    $script:Form.Controls.AddRange(@($discordLbl,$discordOpen,$discordClose,$discordRestart,$diagnostic))
    $dnsHelp=Ui-Button 'DNS INFO' 24 393 145 ([System.Drawing.Color]::FromArgb(63,83,123))
    $autoProfileBtn=Ui-Button 'AUTO PROFILE' 183 393 180 ([System.Drawing.Color]::FromArgb(53,112,143))
    $copyLogBtn=Ui-Button 'COPY LOG' 377 393 129 ([System.Drawing.Color]::FromArgb(70,74,88))
    $openLogsBtn=Ui-Button 'LOG FOLDER' 520 393 142 ([System.Drawing.Color]::FromArgb(70,74,88))
    $script:Form.Controls.AddRange(@($dnsHelp,$autoProfileBtn,$copyLogBtn,$openLogsBtn))
    $securityBtn=Ui-Button 'SECURITY CHECK' 493 427 170 ([System.Drawing.Color]::FromArgb(67,112,87))
    $script:Form.Controls.Add($securityBtn)
    $logLbl=Ui-Label 'EVENT LOG' 26 440 450 25 10
    $script:LogBox=New-Object System.Windows.Forms.TextBox
    $script:LogBox.Location=[System.Drawing.Point]::new(24,470)
    $script:LogBox.Size=[System.Drawing.Size]::new(640,142)
    $script:LogBox.Multiline=$true; $script:LogBox.ScrollBars='Vertical'; $script:LogBox.ReadOnly=$true
    $script:LogBox.Font=[System.Drawing.Font]::new('Consolas',9)
    $script:LogBox.BackColor=[System.Drawing.Color]::FromArgb(32,35,47)
    $script:LogBox.ForeColor=[System.Drawing.Color]::FromArgb(210,218,234)
    $script:Form.Controls.AddRange(@($logLbl,$script:LogBox))

    $old=Load-Json $script:SettingsFile
    if ($null -ne $old) {
        if ($old.Profile -in @('Balanced','Alternative','Gentle')) { $script:ProfileBox.SelectedItem=[string]$old.Profile }
        $script:VoiceCheck.Checked=[bool]$old.Voice
        $script:AutoConflicts.Checked=$false # Retired unsafe saved setting
    }
    $script:ProfileBox.Add_SelectedIndexChanged({ if (!$script:ChangingProfileAutomatically) { Save-Settings } })
    $script:VoiceCheck.Add_CheckedChanged({ Save-Settings })
    $script:AutoConflicts.Add_CheckedChanged({ Save-Settings })
    $script:StartButton.Add_Click({ Start-AutoConnection })
    $script:StopButton.Add_Click({ Cancel-AutoTrial 'user pressed STOP'; [void](Stop-Bypass) })
    $script:RestartButton.Add_Click({ Cancel-AutoTrial 'user pressed RESTART'; if (Stop-Bypass) { Start-Sleep -Milliseconds 300; Start-AutoConnection } else { Log 'Restart cancelled: cleanup failed.' } })
    $installBtn.Add_Click({
        if (Engine-Available) { Log 'Engine is already installed; no files were changed.'; return }
        $choice=[System.Windows.Forms.MessageBox]::Show('Download verified engine from GitHub? YES=download; NO=select a previously downloaded upstream ZIP.','Engine installation','YesNoCancel','Question')
        if ($choice -eq 'Yes') { [void](Install-Engine) }
        elseif ($choice -eq 'No') {
            $dlg=New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter='Official zapret 1.10.4 ZIP|*.zip'
            if ($dlg.ShowDialog() -eq 'OK') { [void](Install-Engine $dlg.FileName) }
            $dlg.Dispose()
        }
    })
    $discordOpen.Add_Click({ Start-Discord })
    $discordClose.Add_Click({ Stop-Discord })
    $discordRestart.Add_Click({ Stop-Discord; Start-Sleep -Milliseconds 400; Start-Discord })
    $diagnostic.Add_Click({ Test-DiscordConnection })
    $dnsHelp.Add_Click({ Show-DnsHelp })
    $autoProfileBtn.Add_Click({ Find-WorkingProfile })
    $copyLogBtn.Add_Click({ Copy-Diagnostics })
    $openLogsBtn.Add_Click({ Open-LogFolder })
    $securityBtn.Add_Click({
        $audit=Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\Security-Check.ps1'
        try {
            Log 'Security check requested: opening visible antivirus and integrity report.'
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoExit -NoProfile -File "'+$audit+'" -ScanWithDefender') -WorkingDirectory (Split-Path -Parent $PSScriptRoot) -ErrorAction Stop | Out-Null
        } catch { Log ('Security check launch failed: '+$_.Exception.Message) }
    })

    $script:Tray=New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.Icon=[System.Drawing.SystemIcons]::Shield; $script:Tray.Visible=$true
    # Construct menu items explicitly. Do not index ContextMenuStrip.Items or cast
    # the result of Items.Add() to [void] before retaining a reference to it.
    # Windows PowerShell can otherwise leave us with an empty collection here.
    $ctx=New-Object System.Windows.Forms.ContextMenuStrip
    try {
        $showItem=[System.Windows.Forms.ToolStripMenuItem]::new('Show DiscordOnly')
        $startItem=[System.Windows.Forms.ToolStripMenuItem]::new('Start bypass')
        $stopItem=[System.Windows.Forms.ToolStripMenuItem]::new('Stop bypass')
        $exitItem=[System.Windows.Forms.ToolStripMenuItem]::new('Exit (leave Discord running)')
        $showItem.Add_Click({ $script:Form.Show(); $script:Form.WindowState='Normal'; $script:Form.Activate() })
        $startItem.Add_Click({ Start-AutoConnection })
        $stopItem.Add_Click({ Cancel-AutoTrial 'tray STOP'; [void](Stop-Bypass) })
        $exitItem.Add_Click({
            Cancel-AutoTrial 'tray Exit'
            $script:Closing=$true
            $script:Form.Close()
        })
        $menuItems=[System.Windows.Forms.ToolStripItem[]]@($showItem,$startItem,$stopItem,$exitItem)
        $ctx.Items.AddRange($menuItems)
        if ($ctx.Items.Count -ne 4) { throw 'Tray menu did not initialize all four items.' }
        $script:Tray.ContextMenuStrip=$ctx
    } catch {
        # A broken tray context menu must never prevent the main app from opening.
        Log ('Tray menu could not be initialized: ' + $_.Exception.Message)
        $script:Tray.ContextMenuStrip=$null
        $ctx.Dispose()
        try {
            $fallback = New-Object System.Windows.Forms.ContextMenuStrip
            $fallbackShow = [System.Windows.Forms.ToolStripMenuItem]::new('Show DiscordOnly')
            $fallbackExit = [System.Windows.Forms.ToolStripMenuItem]::new('Exit (leave Discord running)')
            $fallbackShow.Add_Click({ $script:Form.Show(); $script:Form.WindowState='Normal'; $script:Form.Activate() })
            $fallbackExit.Add_Click({ Cancel-AutoTrial 'tray Exit'; $script:Closing=$true; $script:Form.Close() })
            $fallback.Items.AddRange([System.Windows.Forms.ToolStripItem[]]@($fallbackShow,$fallbackExit))
            $script:Tray.ContextMenuStrip=$fallback
        } catch { Log ('Tray recovery menu also failed: '+$_.Exception.Message) }
    }
    $script:Tray.Add_DoubleClick({ $script:Form.Show(); $script:Form.WindowState='Normal'; $script:Form.Activate() })
    $script:Form.Add_Resize({ if ($script:Form.WindowState -eq 'Minimized') { $script:Form.Hide() } })
    $script:Form.Add_FormClosing({
        param($sender,$eventArgs)
        # Clicking X or Alt+F4 hides the UI; Application.Run keeps the message loop alive.
        # Windows shutdown (which cannot reliably be cancelled) gets best-effort cleanup.
        $systemClosing = $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::WindowsShutDown
        if (!$script:Closing -and !$systemClosing) {
            $eventArgs.Cancel=$true
            $script:Form.Hide()
            Log 'Window hidden to tray; bypass and scoped DNS remain active.'
            if (!$script:ShownTrayTip -and $script:Tray -and $script:Tray.Visible) {
                $script:ShownTrayTip=$true
                try { $script:Tray.ShowBalloonTip(2500, 'DiscordOnly is still running', 'Right-click the tray icon and choose Exit to stop DNS/DPI; Discord stays open.', [System.Windows.Forms.ToolTipIcon]::Info) } catch {}
            }
            return
        }
        if (!$script:CleanShutdown) {
            Cancel-AutoTrial 'application closing'
            $ok=Stop-Bypass
            if (!$ok) {
                Log 'Safe exit blocked because at least one cleanup check failed.'
                if (!$systemClosing) {
                    $eventArgs.Cancel=$true
                    $script:Closing=$false
                    $script:Form.Show()
                    $script:Form.WindowState='Normal'
                    $script:Form.Activate()
                    [void][System.Windows.Forms.MessageBox]::Show(
                        "DiscordOnly could not verify full cleanup. The application remains open so you can retry STOP/Exit.`r`n`r`nSee EVENT LOG. If recovery is needed, run Repair-All.cmd as administrator.",
                        'DiscordOnly - Cleanup warning', 'OK', 'Warning')
                    return
                }
                Log 'Windows shutdown requested; cleanup could not be fully verified. Repair-All.cmd can recover after reboot.'
            } else {
                # Stop only our temporary DNS and DPI processes; leave Discord running.
                $script:CleanShutdown=$true
            }
        }
        if (!$eventArgs.Cancel) {
            Save-Settings
            Log 'DiscordOnly Exit requested: runtime DNS and DPI removed. Discord was NOT stopped.'
        }
    })
    $timer=New-Object System.Windows.Forms.Timer
    $timer.Interval=2000
    $timer.Add_Tick({ Refresh-Status })
    $timer.Start()
    $script:TrialTimer=New-Object System.Windows.Forms.Timer
    $script:TrialTimer.Interval=650
    $script:TrialTimer.Add_Tick({
        try { Monitor-AutoTrial }
        catch {
            Log ('AUTO CONNECT: watchdog error - '+$_.Exception.Message)
            Cancel-AutoTrial 'watchdog exception; left current managed connection for manual inspection'
        }
    })
    try {
        # Automatic recovery after a crash: clean up only verified owned PID/rule.
        # 0.3.0 did not clean up an abandoned winws PID during startup.
        if (Stop-Bypass) {
            Log 'DiscordOnly ready. X hides to tray without stopping. Tray Exit cleans only own DNS and DPI; Discord stays open.'
        } else {
            Log 'Recovery warning: some previous DiscordOnly resources need manual repair.'
            [void][System.Windows.Forms.MessageBox]::Show(
                'Previous DiscordOnly resources could not be cleaned automatically. Review EVENT LOG and run Repair-All.cmd if necessary.',
                'DiscordOnly - Recovery warning', 'OK', 'Warning')
        }
    } catch { Log ('Startup runtime cleanup warning: '+$_.Exception.Message) }
    Refresh-Status
    # ShowDialog() quits its modal loop when Hide() is called, even if FormClosing
    # was cancelled. Application.Run(Form) retains the Windows message loop while
    # hidden in the tray; ONLY explicit Exit closes the main form.
    [System.Windows.Forms.Application]::Run($script:Form)
} finally {
    # Additional safety net for unexpected UI exceptions. This cannot catch power loss
    # or Task Manager process termination; Repair-All.cmd handles that scenario.
    if (!$script:CleanShutdown) {
        try {
            Cancel-AutoTrial 'final cleanup'
            if (Stop-Bypass) {
                Log 'Final cleanup: only DiscordOnly resources were stopped; Discord was left running.'
            } else {
                Log 'FINAL CLEANUP INCOMPLETE: run Repair-All.cmd as administrator.'
                [void][System.Windows.Forms.MessageBox]::Show(
                    'Some DiscordOnly resources may remain. Please run Repair-All.cmd as administrator.',
                    'DiscordOnly - Recovery required', 'OK', 'Warning')
            }
        } catch { Log ('Final cleanup exception: '+$_.Exception.Message) }
    }
    if ($script:TrialTimer) { $script:TrialTimer.Stop(); $script:TrialTimer.Dispose() }
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    if ($script:Tray) { $script:Tray.Visible=$false; $script:Tray.Dispose() }
    if ($script:Form) { $script:Form.Dispose() }
    if ($script:InstanceMutex) { try { $script:InstanceMutex.ReleaseMutex() } catch {} ; $script:InstanceMutex.Dispose() }
}
