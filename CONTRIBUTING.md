# Contributing

Welcome! This project is an early beta focused on selective Discord connectivity on Windows.

1. File a reproducible issue before substantial changes. Include Windows version, ISP (optional), selected DPI profile, whether messaging/voice worked, and the relevant **redacted** event log.
2. Keep network modifications scoped. Do not alter global adapter DNS, hosts, default gateway or firewall without an explicit opt-in and reliable rollback.
3. Ensure closing the window minimizes to tray; exiting the tray app must stop only DiscordOnly-owned infrastructure and leave Discord itself running.
4. Run `python tests/validate_source.py` for structural checks. Build and test on Windows before claiming functional compatibility.
5. Do not commit packaged `winws`/WinDivert binaries, private tokens, or unlicensed third-party code.

Pull requests should explain the user-facing behavior, safety impact, rollback path, and testing performed.
