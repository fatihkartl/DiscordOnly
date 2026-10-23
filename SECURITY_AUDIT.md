# Security checks — DiscordOnly v0.3.5 beta

This is a **development security hardening release, not a security certification**.

## What changed
- Launcher verifies a packaged SHA-256 source manifest before loading the main WinForms app and fails closed on missing/mismatched source files.
- User-initiated **SECURITY CHECK** opens a visible PowerShell security report. Antivirus product inventory uses Windows Security Center. Microsoft Defender *custom scan* is requested **only if Defender AV is active**; with Kaspersky it is intentionally skipped, and the user must scan via Kaspersky's UI. The report never claims that an AV scan being requested means clean.
- Automatic termination of other DPI tools is removed, even when older settings requested it. Every conflict-process shutdown requires user approval.
- No registry run keys, scheduled tasks, antivirus exclusions, Defender setting modifications, or hidden AV overrides were added.

## Important limitations
- SHA-256 manifest is shipped beside the files and **is not digitally signed**, so it detects accidental changes and simple tampering but **does not establish publisher provenance**. Compare against trusted GitHub release/checksums and consider signed publishing in future.
- The application still launches PowerShell elevated and with hidden console mode for its normal GUI workflow, which antivirus software may flag based on behavior. Do not whitelist it without an independent verdict.
- A separate bundled or runtime-fetched winws/WinDivert dependency still requires upstream validation. Downloaded upstream ZIP checksum is pinned and verified by the existing installer, but pre-existing cached engine files are not revalidated against a vendor-signed hash.
- Tests in this repository are static/integrity checks. **No live Windows Defender, Kaspersky or independent malware scanner has been executed in this Linux build environment.**
- If an antivirus flags any component, STOP. Do not disable protection, do not add an exclusion, and share detection details (without personal information) for review.

## How to check locally
1. Extract the complete source/release ZIP. Run Security-Check.cmd before using DiscordOnly; review %LOCALAPPDATA%\DiscordOnly\security-check.txt.
2. If Microsoft Defender is active, the script attempts a custom scan. Review Windows Security > Virus & threat protection > Protection history.
3. If Kaspersky is active, right-click the extracted folder and scan using Kaspersky, then review its detection report. Its behavior monitor may still flag the elevated executable at runtime.
4. Do not run DiscordOnly when checksum verification fails or the antivirus reports a threat.

**This report is not proof that DiscordOnly is free of malware.**
