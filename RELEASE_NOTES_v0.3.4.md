# DiscordOnly v0.3.4 — Safe Auto Connect (Beta)

> **Beta / pre-release.** Windows connectivity and Discord voice have not been independently validated across Internet service providers. Please test and report reproducible issues.

## What's included

- 🔐 **Discord-focused DNS:** temporary Windows NRPT rules and local encrypted DNS-over-HTTPS resolution; no manual adapter-wide DNS changes.
- ⚡ **DPI profiles:** Balanced, Alternative and Gentle (winws/zapret).
- 🧠 **Conservative automatic fallback:** preserves a profile when Discord HTTPS works; delayed Discord window appearance alone no longer triggers profile switching.
- 💬 **Discord launch:** attempts to open Discord after START.
- 🖥️ **System tray:** clicking X hides the manager and keeps its connection alive.
- 🛑 **Clean Exit:** stops DiscordOnly-owned DNS/DPI infrastructure while leaving Discord itself running.
- 🧰 **Diagnostics and recovery:** connection logs, DNS checks and Repair-All.cmd.
- 🔕 **Silent startup:** Start-Silent.vbs avoids an unnecessary visible PowerShell console.

## Installation (source package)

1. Download **Source code (zip)** from this release once it is published, and extract all files.
2. Run `Start-Silent.vbs` and approve the Windows UAC prompt.
3. Select Balanced and click START. Test text chat and voice separately.
4. Click X to hide; tray Exit stops only the bypass infrastructure, not Discord.

The *source archive* may download the pin-verified upstream DPI engine on first use. The `DiscordOnly-Windows-Offline.zip` packaged Windows executable is **not yet available unless attached to this release by a successful Windows CI build**. Do not confuse the source ZIP with a precompiled app.

## Limitations

- Administrator permission required.
- NRPT rules are domain scoped, not process scoped.
- HTTPS success cannot prove login or voice chat success.
- No universal ISP compatibility or guaranteed zero impact on gaming.
- Crash/forced exit may require `Repair-All.cmd`.
- Includes third-party components and licenses described in `THIRD_PARTY_NOTICES.md`.

**Source:** https://github.com/fatihkartl/DiscordOnly

**Issues:** https://github.com/fatihkartl/DiscordOnly/issues
