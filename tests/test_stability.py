"""Static safety guards for v0.3.6; not a Windows or real-network test."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]
s=(p/'app/DiscordOnly.ps1').read_text('utf-8-sig')
dns=(p/'app/DiscordDnsProxy.cs').read_text()
assert "Version = '0.3.6'" in s
assert 'function Watchdog-Tick {' in s
assert 'function Watchdog-OwnNrptPresent {' in s
assert 'function Watchdog-RecordHasLiveUnknownPid(' in s
assert '$script:WatchdogTimer.Interval=10000' in s
assert '$script:WatchdogMisses -lt 2' in s
assert '$script:WatchdogRecoveryHistory.Count -ge 2' in s
assert '[DateTime]::UtcNow.AddMinutes(-10)' in s
assert '$script:WatchdogEnabled=$false' in s[s.index('function Stop-Bypass {'):s.index('function Save-Settings {')]
assert 'if ($script:AutoTrial.Active)' not in s[s.index('function Watchdog-Tick {'):s.index('function Find-WorkingProfile {')]
w=s[s.index('function Watchdog-Tick {'):s.index('function Find-WorkingProfile {')]
assert 'if ($null -ne $script:AutoTrial -and $script:AutoTrial.Active)' in w
assert 'Process-Conflicts' in w
assert 'Stop-Bypass' in w and 'Start-Bypass -AutoLaunch $false -QuietErrors $true' in w
assert 'Watchdog-RecordHasLiveUnknownPid' in w
assert all(x not in w for x in ('Stop-Discord','Start-Discord','Next-TrialProfile','Find-WorkingProfile','Set-DnsClientServerAddress','Test-GatewayQuick'))
assert 'if ($script:WatchdogEnabled)' in s
assert 'Failure(packet, questionEnd, 2); // SERVFAIL' in dns
assert 'Interlocked.Increment(ref inFlight) > 24' in dns
print('v0.3.6 watchdog static guards passed. Windows runtime/voice/ISP reliability NOT verified.')
