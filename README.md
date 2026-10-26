<!-- DiscordOnly · Windows connectivity utility -->
<div align="center">

# 🛡️ DiscordOnly
### Discord-first connectivity for Windows

**Encrypted DNS · Targeted DPI strategies · Automatic Discord launch · Safe tray control**

[![Version](https://img.shields.io/badge/version-v0.3.6-5865F2?style=for-the-badge)](https://github.com/fatihkartl/DiscordOnly/releases)
[![Beta](https://img.shields.io/badge/status-BETA-F59E0B?style=for-the-badge)](https://github.com/fatihkartl/DiscordOnly/releases)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows)](https://github.com/fatihkartl/DiscordOnly)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=for-the-badge&logo=powershell)](https://github.com/fatihkartl/DiscordOnly)
[![MIT](https://img.shields.io/badge/license-MIT-22C55E?style=for-the-badge)](LICENSE)

[**📦 Releases**](https://github.com/fatihkartl/DiscordOnly/releases) · [**🐛 Issues**](https://github.com/fatihkartl/DiscordOnly/issues) · [**⚙️ Builds**](https://github.com/fatihkartl/DiscordOnly/actions) · [**🇹🇷 Türkçe**](#-türkçe) · [**🇬🇧 English**](#-english)

</div>

---

> [!IMPORTANT]
> **Beta software.** DiscordOnly v0.3.6 has passed *structural source checks*, but its latest behavior has **not** been independently verified on Windows or across different ISPs. One older configuration worked on one PC. Discord voice, game compatibility and safe cleanup must be tested on each machine. No universal bypass guarantee.

## 🇹🇷 Türkçe

**DiscordOnly**, Windows için Discord bağlantısına odaklanan bir DNS + DPI yönetim arayüzüdür. Tüm bilgisayarı VPN'e yönlendirmek yerine Discord alan adları için geçici Windows DNS ilkeleri (**NRPT**), yerel **DNS-over-HTTPS** çözümleyicisi ve seçilebilir **winws/zapret** profilleri kullanır.

### ✨ Özellikler

| | Özellik | Detay |
|---|---|---|
| 🔐 | Discord'a özel DNS | Ağ kartının DNS ayarını değiştirmeden geçici NRPT kuralı |
| ⚡ | DPI profilleri | **Balanced**, **Alternative**, **Gentle** |
| 🧠 | Güvenli Auto Connect | HTTPS başarılıysa profili korur; yavaş açılan Discord penceresini başarısızlık saymaz |
| 💬 | Otomatik Discord | START başarılı olunca Discord'u başlatmayı dener |
| 🎤 | Ses desteği | İsteğe bağlı Discord UDP/STUN stratejisi; gerçek ses testi gerekir |
| 🎮 | Seçici filtreleme | Genel VPN yok; **oyunlara sıfır etki garantisi yok** |
| 🖥️ | Sistem tepsisi | **X** ile gizlenir, bağlantı çalışmaya devam eder |
| 🛑 | Güvenli çıkış | **Exit**, uygulamanın DNS/DPI altyapısını kapatır; **Discord'u kapatmaz** |
| 🧰 | Tanılama ve onarım | DNS/HTTPS testleri, loglar, `Repair-All.cmd` |
| 🔕 | Sessiz başlatma | `Start-Silent.vbs`, ayrıca Windows paketi için konsolsuz EXE başlatıcı |

### 📦 Kurulum

1. [**Releases sayfasını aç**](https://github.com/fatihkartl/DiscordOnly/releases). Varsa **DiscordOnly-Windows-Offline.zip** dosyasını indir. Henüz yayımlanmadıysa depoyu ZIP olarak indir; bu durumda motor ilk açılışta indirilir.
2. ZIP'i **tamamen çıkar**. Dosyaları arşiv içinden çalıştırma.
3. `Start-Silent.vbs` veya Windows paketindeki `DiscordOnly.exe` ile başlat; yönetici iznini onayla.
4. **Balanced** profilini seçip **START**'a bas. Discord otomatik açılmayı deneyecek.
5. Discord mesajlaşma ve sesli görüşmeyi ayrı ayrı test et.
6. **X → tepsiye gizle**; **tepsiden Exit → uygulama altyapısını temizle, Discord açık kalsın**.

**Sorun olursa:** `Start-Debug.cmd` ile hata kaydına bak. Uygulama beklenmedik kapanıp DNS ilkesi kaldıysa yönetici olarak `Repair-All.cmd` çalıştır.

### 🔄 Profil seçimi

START bağlantı durumuna göre **muhafazakâr HTTPS kontrollü** geçiş kullanır. Discord'un yavaş açılması tek başına profil değiştirme sebebi değildir. HTTPS başarısı mesajlaşmanın veya sesin çalıştığını kesin kanıtlamaz; **AUTO PROFILE** ayrıca elle çalıştırılabilen bir tanılama aracıdır.

### ⚠️ Sınırlar ve güvenlik

- **Windows 10/11** ve ağ yönetimi için **yönetici izni** gerekir.
- NRPT, *uygulama başına değil alan adı bazlıdır*. Aynı alan adlarını kullanan diğer uygulamalar da kuraldan etkilenebilir.
- WinDivert bazı başka ağ paketlerini inceleyebilir. Ping ve oyun bağlantılarını ayrıca kontrol et.
- Sesli görüşme için gerçek Discord UDP bağlantısı testi gereklidir.
- Çökme veya zorla kapatmadan sonra otomatik temizlik garanti değildir; `Repair-All.cmd` bulunur.
- Motor resmi **Flowseal 1.10.4** sürümünden SHA-256 ile doğrulanarak kurulur; üçüncü taraf koşulları için [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) dosyasına bak.
- Discord Inc. ile ilişkili ya da Discord tarafından onaylanmış bir proje değildir.

## 🇬🇧 English

**DiscordOnly** is a Windows PowerShell/WinForms manager for Discord-focused connectivity. It combines temporary domain-scoped **NRPT** rules, a loopback **DNS-over-HTTPS** resolver and selectable **winws/zapret** DPI strategies — without a system-wide VPN.

**Included:** three TCP profiles, optional Discord UDP/STUN treatment, automatic Discord launch, conservative HTTPS-based fallback, tray minimize, safe cleanup that **leaves Discord running**, diagnostic logs and repair scripts.

**Quick start:** Download the Windows offline ZIP from [Releases](https://github.com/fatihkartl/DiscordOnly/releases) when available, extract it, start `DiscordOnly.exe` or `Start-Silent.vbs`, approve UAC and press **START**. If using the source ZIP, the verified engine may be downloaded on first use.

**Limits:** HTTPS success is not proof of voice/chat readiness. Neither universal ISP coverage nor zero impact on gaming is guaranteed. Requires administrator permissions and real-world testing. This is a **beta** project.

### What a clean Exit does

The tray **Exit** shuts down only DiscordOnly-owned DNS/DPI processes, removes its temporary NRPT rules and **leaves Discord running**. NRPT routing is domain-scoped, **not per-process**. This project is **not universally compatible** with every ISP. A forced termination may require `Repair-All.cmd`.


## 🛠️ Connection stability — v0.3.6 beta

A new **conservative watchdog** checks DiscordOnly-owned `winws` and DNS-proxy processes and its temporary NRPT rule every 10 seconds. It waits for two consecutive failed checks before any repair. If ownership is verified, it safely tears down only its own infrastructure and attempts to restore the **same profile and voice setting**, leaving Discord running. Automatic recovery is limited to **two attempts per 10 minutes**; unknown process ownership, unrelated DPI tools, and missing engine binaries **block** automatic repair.

**No automatic profile switching for brief HTTPS failures or voice-channel disconnects.** A running DPI/DNS process alone does not prove Discord works. For recurrent disconnects, collect `app.log` and `dns-proxy.log` **before restarting** and see [STABILITY_DIAGNOSTICS.md](STABILITY_DIAGNOSTICS.md). STOP and tray Exit disable automatic reconnection.

**This is an unverified beta:** cross-ISP, Kaspersky, voice stability and Windows end-to-end testing remain outstanding.

## 🛡️ Security Check — v0.3.6 Beta

**This is a hardening update, not an antivirus clearance or security certification.**

Before starting the app, run `Security-Check.cmd`. The script displays installed antivirus products, checks the SHA-256 integrity of 17 packaged source/launch files, and attempts a Microsoft Defender custom scan **only if Defender is active**. When Kaspersky is installed, Defender can be inactive; scan the extracted folder from Kaspersky's interface and check the Kaspersky event/quarantine details.

A failing integrity check **blocks DiscordOnly from launching**. The application will no longer automatically kill other DPI programs without consent (old settings cannot re-enable that behavior). The existing DNS, voice, tray and profile methods are otherwise unchanged.

A local unsigned SHA-256 manifest is **not proof of publisher identity**, and neither a clean hash check nor a successful Defender scan makes the application universally safe. If any antivirus detects a threat, stop using the package; **do not disable antivirus or whitelist the app** to make it work.

See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for the threat-model limitations and `%LOCALAPPDATA%\DiscordOnly\security-check.txt` for local reports. Until independent Windows/AV testing passes, v0.3.6 should be treated as **unverified beta**.

## 🛠️ Development & CI

- **App:** Windows PowerShell 5.1 / Windows Forms
- **Network:** Windows NRPT, local DoH, winws/zapret, WinDivert
- **Testing:** `python tests/validate_source.py` (static checks only)
- **Windows CI:** PowerShell parser checks, C# launcher compilation, verified upstream download and offline ZIP packaging
- **Release:** GitHub Actions release builds remain blocked by an account billing restriction; do not treat this beta as verified

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for runtime dependencies and [LICENSE](LICENSE) for the original project's MIT-licensed portions.

---

<div align="center">

**Built with care for selective connectivity — not affiliated with Discord.**

[⭐ Star](https://github.com/fatihkartl/DiscordOnly) · [🐛 Report a bug](https://github.com/fatihkartl/DiscordOnly/issues/new) · [📦 Download](https://github.com/fatihkartl/DiscordOnly/releases)

</div>
