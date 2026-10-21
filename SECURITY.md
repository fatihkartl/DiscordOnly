# Security

DiscordOnly requires administrator rights to manage Windows NRPT rules, WinDivert and selected local processes. Only install copies from this repository and verify upstream components.

The installer downloads a pinned Flowseal 1.10.4 archive with SHA-256 validation; official third-party software is separately attributed in `THIRD_PARTY_NOTICES.md`.

Do not include authentication tokens, personal network information, or Discord credentials in bug reports. The logs may include addresses and process paths; review and redact them first.

If an unexpected crash leaves an application-owned DNS policy or process, run `Repair-All.cmd` as administrator after closing DiscordOnly.

For private security reports, use GitHub's private vulnerability reporting if enabled in this repository, or contact the maintainer through a non-public channel. Do not post exploit details in a public issue.
