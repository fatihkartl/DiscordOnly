"""Cross-platform structural tests. Real Windows/ISP tests still required."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ps = (ROOT / 'app' / 'DiscordOnly.ps1').read_text('utf8')
proxy = (ROOT / 'app' / 'DiscordDnsProxy.cs').read_text('utf8')
proxy_ps = (ROOT / 'app' / 'DiscordDnsProxy.ps1').read_text('utf8')
recovery = (ROOT / 'tools' / 'Repair-All.ps1').read_text('utf8')

# GUI and upstream regressions
assert 'Set-StrictMode -Version Latest' in ps
assert '[System.Drawing.Point]::new($X,$Y)' in ps
assert '[System.Drawing.Size]::new(700,675)' in ps
assert 'New-Object System.Drawing.Point(' not in ps
assert (ROOT / 'Start-Debug.cmd').exists()
assert 'Report-StartupFailure' in (ROOT / 'app' / 'launcher.ps1').read_text('utf8')
assert '$ctx.Items[0]' not in ps and '$ctx.Items[1]' not in ps
assert '[System.Windows.Forms.ToolStripMenuItem]::new' in ps
assert '$ctx.Items.AddRange($menuItems)' in ps
assert 'Stop-Conflicts' in ps and 'Owned-Process' in ps
assert '--hostlist-domains=$domains' in ps
assert '--filter-l7=discord,stun' in ps
assert 'WinDivert64.sys' in ps and '--wf-tcp=$tcpPorts' in ps
assert '291af673bd0238506f9548e0e94ca0abf244000f4c9a06960544fb01c5f97b34' in ps
assert not (ROOT / 'engine').exists(), 'Do not package unverified engine binaries'

# Discord-only DNS: don't change adapter-wide DNS, hosts, firewall, or proxy.
assert 'function Start-DnsRoute' in ps and 'function Stop-DnsRoute' in ps
assert 'Add-DnsClientNrptRule' in ps and 'Remove-DnsClientNrptRule' in ps
assert "-NameServers @('127.0.0.1')" in ps
assert 'DnsRuleLabel' in ps
assert 'Remove-OwnNrptRules' in ps
assert 'Save-Json $script:DnsRuntimeFile' in ps
assert 'Test-DnsBlocked' in ps and '195.175.254.2' in ps
assert 'Resolve-DnsName -Server 127.0.0.1' in ps
assert ps.index('Start-DnsRoute\n        $args') < ps.index('Start-Process -FilePath $exe -ArgumentList ($args -join')
assert 'AutoOpenDiscord.Checked' in ps
assert 'START succeeded; opening Discord automatically.' in ps
assert 'Set-DnsClientServerAddress' not in ps
assert 'netsh' not in ps.lower()
assert 'Set-Content -LiteralPath $env:windir' not in ps
assert 'https://1.1.1.1/dns-query' in proxy and 'https://1.0.0.1/dns-query' in proxy
assert '127.0.0.1:53' in proxy and 'IPAddress.Loopback, 53' in proxy
assert 'request.ContentType = "application/dns-message"' in proxy
assert 'request.Proxy = null' in proxy
assert 'ServerCertificateValidationCallback' not in proxy
assert 'SslPolicyErrors' not in proxy
assert 'Allowed(name)' in proxy and 'Failure(packet, questionEnd, 5)' in proxy
assert 'Add-Type -TypeDefinition' in proxy_ps
assert 'Remove-DnsClientNrptRule' in recovery
assert 'Start-Process -FilePath (Join-Path $PSHOME' in recovery and '-Verb RunAs' in recovery
assert (ROOT / 'Repair-DNS.cmd').is_file()
# Confirm we didn't accidentally promise independent per-process DNS: NRPT is domain-scoped.
readme = (ROOT / 'README.md').read_text('utf8')
assert 'not per-process' in readme
assert 'universally compatible' in readme
assert 'Repair-All.cmd' in readme
assert 'v0.3.6' in readme

# Basic delimiter safety: ensure odd number of here-string opening/closing markers not introduced.
for filename in (ROOT / 'app').glob('*.ps1'):
    src=filename.read_text('utf8')
    assert src.count("@'\n")==src.count("\n'@"), filename
    assert src.count('@"\n')==src.count('\n"@'), filename
print('Source structural checks passed. Windows PowerShell/C# compilation & runtime NOT verified here.')

# 0.3.0 regression rules: hidden GUI with explicit opt-in auto strategies.
silent = (ROOT / 'Start-Silent.vbs').read_text('utf8')
launcher = (ROOT / 'app' / 'launcher.ps1').read_text('utf8')
assert 'WScript.Shell' in silent and 'shell.ShellExecute exe, arguments, root, "runas", 0' in silent
assert '-WindowStyle Hidden' in silent and '-WindowStyle Hidden' in launcher
assert 'Start-Silent.vbs' in (ROOT / 'Start.cmd').read_text('ascii')
assert 'function Find-WorkingProfile' in ps and 'function Test-GatewayQuick' in ps
assert 'function Start-Bypass([bool]$AutoLaunch = $true, [bool]$QuietErrors = $false)' in ps
assert 'Start-Bypass -AutoLaunch $false' in ps
assert 'function Copy-Diagnostics' in ps and 'function Open-LogFolder' in ps
assert 'AUTO PROFILE' in ps and 'COPY LOG' in ps and 'LOG FOLDER' in ps
assert 'Find-WorkingProfile' in ps and 'AUTO PROFILE: No HTTPS-confirmed profile' in ps
assert 'Set-DnsClientServerAddress' not in ps
assert 'start.Verb = "runas"' in (ROOT / 'launcher' / 'DiscordOnlyLauncher.cs').read_text()
assert '/target:winexe' in (ROOT / '.github' / 'workflows' / 'windows-portable.yml').read_text()
print('v0.3.x hidden launcher + opt-in profile checks passed.')

# 0.3.1 teardown rules: visible X hides, explicit Exit cleans up and blocks on errors.
assert "$script:Version = '0.3.6'" in ps
assert '$script:Form.Add_FormClosing' in ps
assert '$eventArgs.Cancel=$true' in ps and '$script:Form.Hide()' in ps
assert '$script:Tray.Visible=$true' in ps
assert 'Exit (leave Discord running)' in ps
assert "if (!$script:Closing -and !$systemClosing)" in ps
assert '$ok=Stop-Bypass' in ps
assert 'if (!$ok)' in ps and "Log 'Safe exit blocked" in ps
assert 'Stop-DnsRoute' in ps and 'Remove-OwnNrptRules' in ps
assert 'WaitForExit(3000)' in ps
assert 'function Stop-ManagedDiscord' not in ps and 'ManagedDiscordSinceUtc' not in ps
assert '$script:CleanShutdown=$true' in ps
assert 'function Stop-Bypass {' in ps and 'return $false' in ps
assert 'Refusing to kill an unknown process' in ps
assert (ROOT / 'Repair-All.cmd').is_file()
assert 'Remove-DnsClientNrptRule' in recovery and 'Clear-DnsClientCache' in recovery
assert 'engine\\bin\\winws.exe' in recovery and 'Win32_Process' in recovery
assert 'ReleaseMutex' in recovery and 'owned-dns.json' in recovery
assert 'Same-Path' in recovery and 'WaitForExit' in recovery
assert 'Repair-All.cmd' in (ROOT/'.github'/'workflows'/'windows-portable.yml').read_text('utf8')
assert 'What a clean Exit does' in readme and 'DiscordOnly' in readme
print('v0.3.2 tray lifecycle and verified cleanup checks passed (static only).')

# 0.3.2 regressions: X must not exit modal loop and cleanup must leave Discord alone.
assert '[System.Windows.Forms.Application]::Run($script:Form)' in ps
assert '[void]$script:Form.ShowDialog()' not in ps
assert '$eventArgs.Cancel=$true' in ps and '$script:Form.Hide()' in ps
assert 'Exit (leave Discord running)' in ps
assert 'Stop-ManagedDiscord' not in ps
assert 'Discord was NOT stopped' in ps
assert 'Discord process detected after automatic launch.' in ps
assert 'START succeeded; opening Discord automatically.' in ps
assert '$script:AutoOpenDiscord.Enabled=$false' in ps
assert 'function Stop-Discord {' in ps   # explicit manual button stays
# START handler must not call Stop-Discord (manual controls may do so).
start_handler=ps[ps.index('function Start-Bypass('):ps.index('function Stop-Bypass {')];assert 'Stop-Discord' not in start_handler
# Strong event handling: explicit tray exit sets flag before closing the main form.
assert '$script:Closing=$true' in ps and '$script:Form.Close()' in ps
assert 'shell.ShellExecute exe, arguments, root, "runas", 0' in silent
assert 'shell.Run cmd' not in silent
print('v0.3.2 X/tray/preserve-Discord and faster elevated-launch regressions passed (static only).')

# v0.3.4: safe fallback does not use slow/missing Discord windows as failure.
assert 'function Start-AutoConnection {' in ps
assert 'function Start-TrialProfile {' in ps
assert 'function Next-TrialProfile([string]$Reason)' in ps
assert 'function Monitor-AutoTrial {' in ps
assert 'function Finish-AutoTrial([bool]$Success)' in ps
assert 'function Hold-AutoTrial([string]$Reason)' in ps
assert 'function Cancel-AutoTrial([string]$Reason' in ps
assert 'function Poll-TrialProbe {' in ps
assert 'BeginGetResponse($null, $null)' in ps
assert 'function Test-DiscordClientWindow' not in ps
assert 'if ($trial.GatewayOK -and $clientReady)' not in ps
monitor=ps[ps.index('function Monitor-AutoTrial {'):ps.index('function Start-AutoConnection {')]
assert 'if ($trial.GatewayOK)' in monitor
assert 'Finish-AutoTrial $true' in monitor
assert monitor.index('if ($trial.GatewayOK)') < monitor.index('if ($trial.ClientSeen -and $now -ge $trial.Deadline)')
assert 'Hold-AutoTrial' in monitor
assert 'if ($trial.ClientSeen -and $now -ge $trial.Deadline)' in monitor
assert 'if ($null -eq (Owned-DnsProcess))' in monitor
starttrial=ps[ps.index('function Start-TrialProfile {'):ps.index('function Next-TrialProfile(')]
assert '$trial.Deadline=[DateTime]::MaxValue' in starttrial
assert '$trial.ClientSeen=[bool](Discord-Running)' in starttrial
assert '$trial.LaunchDeadline=[DateTime]::UtcNow.AddSeconds(20)' in starttrial
assert '$trial.Deadline=[DateTime]::UtcNow.AddSeconds(10)' in starttrial
finish=ps[ps.index('function Finish-AutoTrial('):ps.index('function Start-TrialProfile {')]
assert 'Stop-Bypass' in finish and 'Start-Bypass -AutoLaunch $true -QuietErrors $true' in finish
assert 'no profile passed the readiness heuristic. Stopping own bypass' not in finish
assert 'gateway HTTPS is reachable' in finish
assert 'if (!(Stop-Bypass)) {' in ps[ps.index('function Next-TrialProfile('):ps.index('function Monitor-AutoTrial')]
assert 'Start-AutoConnection' in ps[ps.index('$script:StartButton.Add_Click('):]
assert "Cancel-AutoTrial 'user pressed STOP'" in ps
assert "Cancel-AutoTrial 'tray Exit'" in ps
assert '$script:ChangingProfileAutomatically' in ps
trial_code=ps[ps.index('# START watchdog checks'):ps.index('# Explicit, user-initiated discovery;')]
assert 'Stop-Discord' not in trial_code
assert 'Set-DnsClientServerAddress' not in trial_code
assert '[System.Windows.Forms.Application]::Run($script:Form)' in ps
print('v0.3.4 conservative HTTPS-only success, delayed failover and original-profile recovery structural checks passed (static only).')
