# Changelog

## v0.3.5 — Security hardening (beta; not AV-certified)
- Visible SECURITY CHECK opens local checksum/antivirus report; attempts Defender custom scan only when active.
- Startup fails closed if one of the pinned source/launcher files is missing or checksum-mismatched.
- Disabled previously saved automatic termination of other DPI tools; explicit confirmation now required.
- Security checks and CI regression workflow added. No antivirus or Windows runtime clearance is claimed.
- DNS, DPI, Discord startup and system tray connection logic retained from v0.3.4.

## v0.3.4 — Safe Auto Connect (beta)
- Preserve the selected DPI strategy when Discord HTTPS responds successfully, even while Discord is still updating or has no visible window.
- Do not switch profiles simply because Discord's window is slow to appear.
- A failed HTTPS check may allow conservative alternative strategy trials only under guarded conditions.
- Restore the original profile if automatic trials cannot confirm another profile.
- Maintain Discord-focused NRPT + DoH, separate voice option, silent launching, tray lifecycle, and safe Exit that leaves Discord running.
- Source structural tests passed; real Windows, voice and cross-ISP tests remain necessary.

Earlier stages: v0.3.3 automatic retries; v0.3.2 X/tray lifecycle and Discord-preserving Exit; v0.2.0 scoped DNS resolution.
