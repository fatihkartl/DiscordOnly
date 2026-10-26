# Connection stability — investigate before restarting

DiscordOnly v0.3.6 has a **conservative owned-process watchdog**, not a full Discord chat/voice checker. A running winws and DNS proxy cannot prove that Discord's gateway or voice is healthy.

## If Discord disconnects after some time

1. **Do not restart immediately.** Note the local time and whether the issue affects text, updates, voice, or all of Discord.
2. Run **DNS + HTTPS Test** in the application. This checks DNS and HTTPS, **not** voice UDP.
3. Save `%LOCALAPPDATA%\DiscordOnly\app.log` and `%LOCALAPPDATA%\DiscordOnly\dns-proxy.log`. Remove personal paths, addresses, and private data before sharing.
4. Record ISP, Windows version, network type, selected profile, voice option, and any antivirus/DPI alerts.
5. Test whether rejoining the voice channel solves a voice-only outage without restarting DiscordOnly.

## Automatic recovery policy

- Every 10 seconds, inspect **verified app-owned winws and DNS proxy processes and the app's NRPT rule**.
- Only two consecutive failed checks allow self-repair. On confirmed process/rule disappearance, stop only owned infrastructure and retry the **same** profile. Discord is **not** closed/restarted.
- Other DPI tools, unverifiable PID ownership, missing or quarantined engine files, cleanup failures, and 2 automated retries in 10 minutes **block** recovery.
- HTTPS timeouts, slow Discord startup, server trouble and voice-only disconnects do not cause background profile switching.
- STOP and tray Exit disable recovery. Tray Exit leaves Discord running, but removes the DNS/DPI bypass.
- If the app exits unexpectedly, the included Repair-All.cmd may help **after** investigating antivirus warnings. Do not disable antivirus to force operation.

## Limitations

The original voice UDP rule only covers a narrow port subset. Discord servers and voice routes can change, and a live DNS proxy can still fail to reach its DoH upstream. Neither is reliably diagnosable solely from local process presence. Do not broaden filters to unrelated game traffic blindly.

**This is a beta source-level correction, not a proven fix for every disconnection.** Windows runtime, long voice sessions, multiple ISPs and antivirus behavior remain unverified.
