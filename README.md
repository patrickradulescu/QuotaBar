# QuotaBar

QuotaBar is a small macOS menu-bar app that shows AI usage on the Touch Bar only while a supported AI app is frontmost. It is an original, clean-room implementation with its own code and artwork.

![macOS](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-22c55e)

[English](#quotabar) · [ภาษาไทย](#ภาษาไทย)

## What it does

- Shows used and remaining quota with a compact progress bar.
- Labels Claude's five-hour session, all-model weekly limit, and Fable weekly limit separately.
- Appears for Codex/ChatGPT, Claude Desktop, and Google Antigravity.
- Dismisses immediately when you switch to Safari or another unrelated app.
- Keeps one menu-bar process alive; it does not replace the normal Touch Bar permanently.
- Offers a menu-bar fallback when the private Touch Bar presenter is unavailable.

## Provider status

| Provider | Source | Status |
| --- | --- | --- |
| Codex | Documented `codex app-server` method `account/rateLimits/read` | Supported |
| Claude | Official Claude Code `/usage` screen in an isolated safe-mode PTY | Beta |
| Gemini / Antigravity | Verifies the Google-signed app and opens its official Settings → Models quota screen | Manual handoff |

QuotaBar never implements provider authentication. Sign in with each supported provider's official app or CLI first.

Antigravity currently exposes its five-hour and weekly baseline quota only inside the official app. It does not provide a supported headless quota command or public API. QuotaBar therefore detects the genuine Google-signed app and offers **Open Antigravity Models…**, but does not read Google OAuth tokens, app databases, private loopback services, or scrape the screen. Exact automatic Gemini percentages will be added only when Google publishes a safe machine-readable interface.

## Privacy and security

QuotaBar does **not** request Full Disk Access, Accessibility, Screen Recording, Input Monitoring, Automation, administrator access, or your passwords.

- Provider commands are launched directly, never through a shell.
- Raw terminal output is kept in memory only and is never logged or written to disk.
- Only normalized provider state, percentages, and reset times are cached in `~/Library/Application Support/QuotaBar/status.json`.
- There is no analytics SDK, telemetry, automatic installer, or remote QuotaBar server.
- **Check for Updates…** contacts only GitHub's public release API after the user clicks it. It never downloads or executes release code automatically.
- Supported signed provider binaries are checked before launch where macOS signing information is available.
- Child processes receive a minimal environment rather than the parent app's full environment.

Claude's signed CLI may update its own session/history metadata because `/usage` is an interactive command. QuotaBar reuses one Claude process while an eligible app stays frontmost, never opens those files itself, and stops the helper as soon as you switch away.

If QuotaBar is force-quit, its next launch removes only an orphaned Claude PTY whose full expected argument shape and QuotaBar-specific marker both match. Ordinary Claude sessions are not matched, and cleanup never escalates to `SIGKILL`.

See [SECURITY.md](SECURITY.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the threat model and implementation boundary.

## Requirements

- A Touch Bar Mac running macOS 13 or later.
- Swift 6 / Xcode Command Line Tools to build from source.
- The official Codex and/or Claude Code CLI already authenticated.
- Google Antigravity is optional; its exact quota remains visible in Antigravity Settings → Models.

## Build and install

```bash
git clone https://github.com/patrickradulescu/QuotaBar.git
cd QuotaBar
./scripts/install-local.sh
```

The installer builds a universal (Apple silicon + Intel), ad-hoc-signed local app, copies it to `/Applications/QuotaBar.app`, and opens it. Enable **Launch at Login** from the menu-bar gauge if desired.

## Updates

Choose **Check for Updates…** from the menu-bar gauge. QuotaBar compares its version with the latest public GitHub release using an ephemeral HTTPS session. If a newer version exists, **Open Release** takes you to the verified `patrickradulescu/QuotaBar` release page.

The current public channel is source-only, so QuotaBar intentionally does not show **Update Now** or replace its own app bundle. One-click installation will be enabled only after release binaries are Developer-ID signed, notarized, and protected by signed update metadata.

For development:

```bash
swift build
swift test
./scripts/build-app.sh
```

## Uninstall

Turn off **Launch at Login**, quit QuotaBar, then remove:

```bash
rm -rf /Applications/QuotaBar.app
rm -rf "$HOME/Library/Application Support/QuotaBar"
rm -rf "$HOME/Library/Caches/com.patrickradulescu.QuotaBar"
```

## Distribution caveat

Public AppKit can show an `NSTouchBar` only for the active owning app. Cross-application presentation therefore uses one isolated private AppKit selector. QuotaBar does not load a private framework, but this means it is not suitable for the Mac App Store and may need maintenance after a macOS update.

GitHub source builds are ad-hoc signed. A downloadable release for other Macs should be universal, Developer-ID signed, hardened, and notarized before distribution.

## Clean-room statement

QuotaBar does not contain source code, artwork, resources, credentials, or decompiled output from What The Token or any other third-party quota app. Observable behavior was used only to define product requirements; the implementation and branding were created independently.

## License

MIT © 2026 Patrick Radulescu.

---

## ภาษาไทย

QuotaBar เป็นแอปเมนูบาร์ขนาดเล็กสำหรับ MacBook Pro ที่มี Touch Bar ใช้แสดงปริมาณโควตา AI ที่ใช้ไปและเหลืออยู่ โดยแถบจะแสดงเฉพาะตอนที่เปิดใช้งาน Codex/ChatGPT, Claude Desktop หรือ Google Antigravity อยู่ด้านหน้า เมื่อเปลี่ยนไป Safari หรือแอปอื่น QuotaBar จะคืน Touch Bar ให้ระบบตามปกติ

โปรเจกต์นี้เป็น clean-room implementation ซอร์สโค้ดและงานภาพสร้างขึ้นใหม่ทั้งหมด ไม่ได้คัดลอก source, resource หรือ decompiled output จากแอปอื่น

### ตัวเลขบน Touch Bar หมายถึงอะไร

| ข้อความ | ความหมาย |
| --- | --- |
| `CODEX` | เปอร์เซ็นต์โควตา Codex ที่ใช้ไปและเหลืออยู่ตามข้อมูลจาก Codex app-server |
| `CLAUDE · 5H` | โควตา Claude ของรอบปัจจุบัน 5 ชั่วโมง ตัวเลขใหญ่คือเปอร์เซ็นต์ที่ใช้ไป |
| `LEFT` | เปอร์เซ็นต์ที่ยังเหลือในรอบ 5 ชั่วโมงของ Claude |
| `WK` | เปอร์เซ็นต์โควตา Claude รายสัปดาห์รวมทุกโมเดลที่ใช้ไป |
| `FABLE` | เปอร์เซ็นต์โควตา Claude รายสัปดาห์เฉพาะโมเดล Fable ที่ใช้ไป |
| `GEMINI · OPEN MODELS` | พบแอป Antigravity ทางการแล้ว ให้เปิด Settings → Models เพื่อดูโควตา 5 ชั่วโมงและรายสัปดาห์ |

ตัวอย่าง:

```text
CLAUDE · 5H  3%
97% LEFT · WK 13% · FABLE 25%
```

### สิ่งที่ต้องมีก่อนติดตั้ง

- MacBook Pro ที่มี Touch Bar และใช้ macOS 13 ขึ้นไป
- Xcode Command Line Tools หรือ Swift 6 สำหรับ build จาก source
- แอปหรือ CLI ทางการของ Codex และ/หรือ Claude Code ที่เข้าสู่ระบบเรียบร้อยแล้ว
- Google Antigravity เป็นตัวเลือกเสริมสำหรับ Gemini โดยค่าที่แน่นอนยังดูจาก Settings → Models ในแอปทางการ

หากยังไม่มี Command Line Tools ให้เปิด Terminal แล้วรัน:

```bash
xcode-select --install
```

ควรเปิด Codex CLI และ Claude Code อย่างน้อยหนึ่งครั้งเพื่อเข้าสู่ระบบและทำขั้นตอนเริ่มต้นของผู้ให้บริการให้เสร็จก่อนใช้ QuotaBar

### วิธีติดตั้ง

เปิด Terminal แล้วรัน:

```bash
git clone https://github.com/patrickradulescu/QuotaBar.git
cd QuotaBar
./scripts/install-local.sh
```

สคริปต์จะ build แอปแบบ Universal สำหรับทั้ง Apple silicon และ Intel ติดตั้งไว้ที่ `/Applications/QuotaBar.app` และเปิดแอปให้โดยอัตโนมัติ

หากต้องการใช้ source ของ release 0.3.0 โดยตรง:

```bash
git clone https://github.com/patrickradulescu/QuotaBar.git
cd QuotaBar
git checkout v0.3.0
./scripts/install-local.sh
```

### วิธีใช้งาน

1. เปิด QuotaBar แล้วมองหาไอคอนรูปมาตรวัดบน menu bar
2. เปิด Codex/ChatGPT, Claude Desktop หรือ Google Antigravity ให้เป็นแอปด้านหน้า
3. QuotaBar จะแสดงเปอร์เซ็นต์บน Touch Bar และอัปเดตข้อมูลเป็นระยะ
4. เมื่อเปลี่ยนไป Safari หรือแอปอื่น แถบ QuotaBar จะหายและ Touch Bar ปกติจะกลับมา
5. หากต้องการให้เปิดพร้อมเครื่อง ให้เลือก **Launch at Login** จากเมนูรูปมาตรวัด
6. กด **Refresh Now** จากเมนูเดียวกันเมื่อต้องการขอข้อมูลล่าสุดทันที
7. สำหรับ Gemini ให้เลือก **Open Antigravity Models…** แล้วเปิด Settings → Models เพื่อดูค่า 5 ชั่วโมงและรายสัปดาห์จาก Google โดยตรง

หาก provider แสดง `OFFLINE` ให้ตรวจว่าได้ติดตั้งและเข้าสู่ระบบ CLI ทางการของ provider นั้นแล้ว จากนั้นเปิด CLI ให้ผ่านหน้า setup อย่างน้อยหนึ่งครั้ง

### การตรวจอัปเดต

เลือก **Check for Updates…** จากเมนูรูปมาตรวัด QuotaBar จะเรียกเฉพาะ GitHub Release API สาธารณะหลังจากผู้ใช้กด หากมีรุ่นใหม่ ปุ่ม **Open Release** จะเปิดหน้า release ทางการให้ตรวจสอบและติดตั้ง

ตอนนี้ยังไม่มีปุ่ม **Update Now** เพราะ release เป็น source-only และตัวแอป build แบบ ad-hoc การดาวน์โหลด source แล้วรันอัตโนมัติไม่ปลอดภัย ระบบติดตั้งคลิกเดียวจะเปิดใช้หลังจากมี Developer ID signing, notarization และ metadata อัปเดตที่ลงลายเซ็นแล้วเท่านั้น

### วิธีส่งให้คนอื่นใช้

ส่งลิงก์ repository นี้ให้ผู้ใช้:

```text
https://github.com/patrickradulescu/QuotaBar
```

จากนั้นให้เขาทำตามหัวข้อ **สิ่งที่ต้องมีก่อนติดตั้ง** และ **วิธีติดตั้ง** ด้านบน รุ่นนี้เผยแพร่แบบ source-only จึงยังไม่มีไฟล์ `.dmg` หรือ binary สำหรับกดติดตั้งทันที ผู้ใช้แต่ละคนจะ build แอปบนเครื่องของตัวเอง

สามารถส่งลิงก์ release โดยตรงได้ที่:

```text
https://github.com/patrickradulescu/QuotaBar/releases/tag/v0.3.0
```

### ความเป็นส่วนตัวและความปลอดภัย

QuotaBar ไม่ขอ Full Disk Access, Accessibility, Screen Recording, Input Monitoring, Automation, สิทธิ์ administrator หรือรหัสผ่านของผู้ใช้

- เรียกเฉพาะ executable ทางการของ provider จากตำแหน่งที่กำหนดและตรวจลายเซ็นก่อนใช้งาน
- ไม่อ่านไฟล์ OAuth, cookie, database หรือ container ของแอปอื่น
- ไม่บันทึก raw terminal output ลงดิสก์
- เก็บเฉพาะสถานะ เปอร์เซ็นต์ และเวลา reset ที่ผ่านการ normalize แล้วใน `~/Library/Application Support/QuotaBar/status.json`
- ไม่มี analytics, telemetry, automatic installer หรือ server ของ QuotaBar
- เมนู **Check for Updates…** ติดต่อเฉพาะ GitHub Release API สาธารณะเมื่อผู้ใช้กด และไม่ดาวน์โหลดหรือรันโค้ดอัตโนมัติ

Claude Code อาจอัปเดต session/history ของตัวเองเมื่อใช้คำสั่ง `/usage` แต่ข้อมูลส่วนนั้นถูกจัดการโดย CLI ทางการของ Anthropic และ QuotaBar ไม่ได้เปิดอ่านไฟล์ดังกล่าว

อ่าน threat model ฉบับเต็มได้ที่ [SECURITY.md](SECURITY.md)

### ข้อจำกัดปัจจุบัน

- Google ยังไม่มีคำสั่งหรือ API แบบ headless สำหรับโควตา Antigravity จึงยังไม่แสดงเปอร์เซ็นต์ Gemini อัตโนมัติ QuotaBar ไม่อ่าน OAuth, database, private API หรือทำ OCR/Accessibility scraping
- การแสดง Touch Bar ข้ามแอปใช้ private AppKit selector ที่แยกไว้เฉพาะจุด จึงไม่รองรับ Mac App Store และอาจต้องปรับหลัง macOS อัปเดต
- GitHub Release ปัจจุบันเป็น source-only หากจะแจก binary ให้ผู้ใช้ทั่วไปควรใช้ Developer ID signing และ notarization ก่อน

### ถอนการติดตั้ง

ปิด **Launch at Login**, เลือก **Quit QuotaBar** แล้วรัน:

```bash
rm -rf /Applications/QuotaBar.app
rm -rf "$HOME/Library/Application Support/QuotaBar"
rm -rf "$HOME/Library/Caches/com.patrickradulescu.QuotaBar"
```

### สัญญาอนุญาต

MIT © 2026 Patrick Radulescu
