# QuotaBar

QuotaBar is a small macOS menu-bar app that shows AI usage on the Touch Bar only while a supported AI app is frontmost. It is an original, clean-room implementation with its own code and artwork.

![macOS](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-22c55e)

[English](#quotabar) · [ภาษาไทย](#ภาษาไทย)

## What it does

- Shows used and remaining quota with a compact progress bar.
- Labels Claude's five-hour session, all-model weekly limit, and Fable weekly limit separately.
- Appears for Codex/ChatGPT, Claude Desktop, Google Antigravity, and a supported terminal while its process tree contains a Google-signed `agy`.
- Dismisses immediately when you switch to Safari or another unrelated app.
- Keeps one menu-bar process alive; it does not replace the normal Touch Bar permanently.
- Offers a menu-bar fallback when the private Touch Bar presenter is unavailable.

## Provider status

| Provider | Source | Status |
| --- | --- | --- |
| Codex | Documented `codex app-server` method `account/rateLimits/read` | Supported |
| Claude | Official Claude Code `/usage` screen in an isolated safe-mode PTY | Beta |
| Gemini / Antigravity | Official AGY statusline callback → bundled sanitizer → private normalized cache; signed-AGY terminal activation | Opt-in beta |

QuotaBar never implements provider authentication. Sign in with each supported provider's official app or CLI first.

AGY does not currently provide a headless quota subcommand or public quota API. It does, however, provide a documented custom statusline callback. After explicit setup, AGY invokes QuotaBar's bundled helper and sends its status JSON through standard input. This command replaces AGY's built-in/default statusline or any existing custom statusline while connected. The helper immediately discards every field except Gemini five-hour/weekly remaining fractions, reset times, AGY version, and observation time. QuotaBar never reads Google OAuth tokens, AGY settings, logs, databases, private loopback services, or screen pixels. **Open Antigravity Models…** remains available as a manual fallback.

QuotaBar displays the last quota report received from AGY, not a direct live read of the Antigravity GUI. A value can therefore lag behind Settings → Models until AGY emits another callback. The app accepts that report as live for at most 30 minutes; after that it shows setup/manual guidance instead. Google documents the statusline transport, but its published field table does not yet list the `quota` object emitted by AGY 1.1.1, so this integration is version-sensitive and remains beta.

## Privacy and security

QuotaBar does **not** request Full Disk Access, Accessibility, Screen Recording, Input Monitoring, Automation, administrator access, or your passwords.

- Provider commands are launched directly, never through a shell.
- Raw terminal/statusline payloads are kept in memory only and are never logged or written to disk.
- Normalized provider state is cached in `status.json`; the AGY bridge stores only its minimal quota DTO in `agy-quota.json`. Both live under `~/Library/Application Support/QuotaBar/` with mode `0600` inside a `0700` directory.
- There is no analytics SDK, telemetry, automatic installer, or remote QuotaBar server.
- **Check for Updates…** contacts only GitHub's public release API after the user clicks it. It streams at most 256 KiB, distinguishes network/rate-limit/server/feed failures, and never downloads or executes release code automatically.
- Supported signed provider binaries are checked before launch where macOS signing information is available.
- Codex and Claude probes spawned by QuotaBar receive a minimal allowlisted environment rather than the app's full environment. The AGY bridge is spawned by AGY itself and therefore inherits AGY's process environment; the bridge code never reads, enumerates, logs, or persists environment variables.

Claude's signed CLI may update its own session/history metadata because `/usage` is an interactive command. QuotaBar reuses one Claude process while an eligible app stays frontmost, never opens those files itself, and stops the helper as soon as you switch away. An explicit **Refresh Now** click outside a supported app starts a one-shot refresh and stops its helpers after at most 30 seconds.

If QuotaBar is force-quit, its next launch removes only an orphaned Claude PTY whose full expected argument shape and QuotaBar-specific marker both match. Ordinary Claude sessions are not matched, and cleanup never escalates to `SIGKILL`.

See [SECURITY.md](SECURITY.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the threat model and implementation boundary.

## Requirements

- A Touch Bar Mac running macOS 13 or later.
- Swift 6 / Xcode Command Line Tools to build from source.
- The official Codex and/or Claude Code CLI already authenticated.
- Google Antigravity/AGY is optional. The official Settings → Models screen remains the exact manual fallback.

## Build and install

```bash
git clone https://github.com/patrickradulescu/QuotaBar.git
cd QuotaBar
./scripts/install-local.sh
```

The installer builds a universal (Apple silicon + Intel), ad-hoc-signed local app, copies it to `/Applications/QuotaBar.app`, and opens it. Enable **Launch at Login** from the menu-bar gauge if desired.

## Gemini / AGY setup

1. Install and sign in to the [official Antigravity CLI](https://antigravity.google/download#antigravity-cli).
2. In QuotaBar, choose **Set Up AGY Quota…** and copy the generated command.
3. Paste that `/statusline …QuotaBarAgyBridge` command into the AGY prompt and press Return.
4. Keep AGY running when you want recent Gemini values. QuotaBar shows the last report emitted by AGY, rejects cache data older than 30 minutes, and falls back to setup/manual guidance. It does not guarantee that the value matches the Antigravity GUI between callbacks.

Setup is explicit because AGY supports one active statusline command; the command replaces AGY's built-in/default statusline or any existing custom statusline. Run `/statusline delete` in AGY to disconnect QuotaBar and restore AGY's default statusline. QuotaBar never edits AGY's settings file itself.

When Terminal, iTerm2, Ghostty, WezTerm, Warp, Kitty, or Alacritty is frontmost, QuotaBar checks only same-user process ancestry and the AGY Developer ID signature. It never reads terminal text or commands. Detection is app/process-tree scoped rather than active-tab scoped: an AGY process in any tab or window belonging to the frontmost terminal app can activate QuotaBar even when a different tab is visible. A detached AGY process whose parent is a tmux/server process may not be recognized.

## Updates

Choose **Check for Updates…** from the menu-bar gauge. QuotaBar compares its version with the latest public GitHub release using an ephemeral HTTPS session. If a newer version exists, **Open Release** takes you to the verified `patrickradulescu/QuotaBar` release page. Responses are size-limited while streaming, and timeout, offline, GitHub rate-limit/server, and untrusted-feed failures are reported separately.

The current public channel is source-only, so QuotaBar intentionally does not show **Update Now** or replace its own app bundle. One-click installation will be enabled only after release binaries are Developer-ID signed, notarized, and protected by signed update metadata.

For development:

```bash
swift build
swift test
./scripts/build-app.sh
```

## Uninstall

Run `/statusline delete` in AGY if its bridge is enabled, turn off **Launch at Login**, quit QuotaBar, then remove:

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

QuotaBar เป็นแอปเมนูบาร์ขนาดเล็กสำหรับ MacBook Pro ที่มี Touch Bar ใช้แสดงปริมาณโควตา AI ที่ใช้ไปและเหลืออยู่ โดยแถบจะแสดงเฉพาะตอนที่เปิดใช้งาน Codex/ChatGPT, Claude Desktop, Google Antigravity หรือ terminal ที่มี `agy` ทางการกำลังทำงานอยู่ เมื่อเปลี่ยนไป Safari หรือแอปอื่น QuotaBar จะคืน Touch Bar ให้ระบบตามปกติ

โปรเจกต์นี้เป็น clean-room implementation ซอร์สโค้ดและงานภาพสร้างขึ้นใหม่ทั้งหมด ไม่ได้คัดลอก source, resource หรือ decompiled output จากแอปอื่น

### ตัวเลขบน Touch Bar หมายถึงอะไร

| ข้อความ | ความหมาย |
| --- | --- |
| `CODEX` | เปอร์เซ็นต์โควตา Codex ที่ใช้ไปและเหลืออยู่ตามข้อมูลจาก Codex app-server |
| `CLAUDE · 5H` | โควตา Claude ของรอบปัจจุบัน 5 ชั่วโมง ตัวเลขใหญ่คือเปอร์เซ็นต์ที่ใช้ไป |
| `LEFT` | เปอร์เซ็นต์ที่ยังเหลือในรอบ 5 ชั่วโมงของ Claude |
| `WK` | เปอร์เซ็นต์โควตา Claude รายสัปดาห์รวมทุกโมเดลที่ใช้ไป |
| `FABLE` | เปอร์เซ็นต์โควตา Claude รายสัปดาห์เฉพาะโมเดล Fable ที่ใช้ไป |
| `GEMINI · 5H` | โควตา Gemini รอบ 5 ชั่วโมงจาก AGY ตัวเลขใหญ่คือเปอร์เซ็นต์ที่ใช้ไป ส่วน `WK` คือเปอร์เซ็นต์รายสัปดาห์ที่ใช้ไป |
| `GEMINI · SET UP AGY` | พบ AGY แล้ว แต่ยังไม่ได้เชื่อม statusline bridge กับ QuotaBar |
| `GEMINI · OPEN MODELS` | ข้อมูล AGY ยังไม่พร้อมหรือเก่าเกิน 30 นาที ให้เปิด AGY หรือดู Settings → Models |

ตัวอย่าง:

```text
CLAUDE · 5H  3%
97% LEFT · WK 13% · FABLE 25%
```

### สิ่งที่ต้องมีก่อนติดตั้ง

- MacBook Pro ที่มี Touch Bar และใช้ macOS 13 ขึ้นไป
- Xcode Command Line Tools หรือ Swift 6 สำหรับ build จาก source
- แอปหรือ CLI ทางการของ Codex และ/หรือ Claude Code ที่เข้าสู่ระบบเรียบร้อยแล้ว
- Google Antigravity/AGY เป็นตัวเลือกเสริมสำหรับ Gemini และ Settings → Models ยังเป็นหน้าสำรองทางการ

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

หากต้องการใช้ source ของ release 0.4.1 โดยตรง:

```bash
git clone https://github.com/patrickradulescu/QuotaBar.git
cd QuotaBar
git checkout v0.4.1
./scripts/install-local.sh
```

### วิธีใช้งาน

1. เปิด QuotaBar แล้วมองหาไอคอนรูปมาตรวัดบน menu bar
2. เปิด Codex/ChatGPT, Claude Desktop, Google Antigravity หรือเปิด `agy` ใน terminal ที่รองรับให้เป็นแอปด้านหน้า
3. QuotaBar จะแสดงเปอร์เซ็นต์บน Touch Bar และอัปเดตข้อมูลเป็นระยะ
4. เมื่อเปลี่ยนไป Safari หรือแอปอื่น แถบ QuotaBar จะหายและ Touch Bar ปกติจะกลับมา
5. หากต้องการให้เปิดพร้อมเครื่อง ให้เลือก **Launch at Login** จากเมนูรูปมาตรวัด
6. กด **Refresh Now** จากเมนูเดียวกันเมื่อต้องการขอข้อมูลล่าสุดทันที หากอยู่ในแอปอื่น ปุ่มนี้จะรัน one-shot refresh ตามคำสั่งผู้ใช้และปิด helper ภายในไม่เกิน 30 วินาที
7. สำหรับ Gemini ให้ติดตั้ง/เข้าสู่ระบบ `agy` ทางการ เลือก **Set Up AGY Quota…** ใน QuotaBar แล้วคัดลอกคำสั่ง `/statusline` ไปวางใน AGY หนึ่งครั้ง
8. เมื่อ AGY ทำงาน ตัว helper จะส่งเฉพาะค่า 5 ชั่วโมง/รายสัปดาห์ที่ normalize แล้วให้ QuotaBar; ตัวเลขคือค่าล่าสุดที่ AGY รายงาน จึงอาจไม่ตรงกับหน้า Settings → Models ในทันที และหากข้อมูลเกิน 30 นาที QuotaBar จะไม่แสดงเป็น live
9. ใช้ **Open Antigravity Models…** ดูค่าจากหน้าทางการได้เสมอ และใช้ `/statusline delete` ใน AGY เมื่อต้องการยกเลิกการเชื่อมต่อ

AGY รองรับ statusline command ที่ทำงานอยู่ได้หนึ่งตัว การตั้งค่านี้จึงแทนที่ statusline มาตรฐานของ AGY หรือ custom statusline เดิม QuotaBar ไม่แก้ไฟล์ settings ของ AGY ให้อัตโนมัติ ผู้ใช้เป็นผู้วางคำสั่งและยืนยันเอง ใช้ `/statusline delete` เพื่อยกเลิกการเชื่อมต่อและกลับไปใช้ statusline มาตรฐาน

หาก provider แสดง `OFFLINE` ให้ตรวจว่าได้ติดตั้งและเข้าสู่ระบบ CLI ทางการของ provider นั้นแล้ว จากนั้นเปิด CLI ให้ผ่านหน้า setup อย่างน้อยหนึ่งครั้ง

### การตรวจอัปเดต

เลือก **Check for Updates…** จากเมนูรูปมาตรวัด QuotaBar จะเรียกเฉพาะ GitHub Release API สาธารณะหลังจากผู้ใช้กด หากมีรุ่นใหม่ ปุ่ม **Open Release** จะเปิดหน้า release ทางการให้ตรวจสอบและติดตั้ง รุ่นนี้จำกัด response ขณะรับข้อมูลที่ 256 KiB และแยกข้อความ offline, timeout, rate limit, server error และ feed ที่ไม่ผ่านการตรวจสอบออกจากกัน

ตอนนี้ยังไม่มีปุ่ม **Update Now** เพราะ release เป็น source-only และตัวแอป build แบบ ad-hoc การดาวน์โหลด source แล้วรันอัตโนมัติไม่ปลอดภัย ระบบติดตั้งคลิกเดียวจะเปิดใช้หลังจากมี Developer ID signing, notarization และ metadata อัปเดตที่ลงลายเซ็นแล้วเท่านั้น

### วิธีส่งให้คนอื่นใช้

ส่งลิงก์ repository นี้ให้ผู้ใช้:

```text
https://github.com/patrickradulescu/QuotaBar
```

จากนั้นให้เขาทำตามหัวข้อ **สิ่งที่ต้องมีก่อนติดตั้ง** และ **วิธีติดตั้ง** ด้านบน รุ่นนี้เผยแพร่แบบ source-only จึงยังไม่มีไฟล์ `.dmg` หรือ binary สำหรับกดติดตั้งทันที ผู้ใช้แต่ละคนจะ build แอปบนเครื่องของตัวเอง

สามารถส่งลิงก์ release โดยตรงได้ที่:

```text
https://github.com/patrickradulescu/QuotaBar/releases/tag/v0.4.1
```

### ความเป็นส่วนตัวและความปลอดภัย

QuotaBar ไม่ขอ Full Disk Access, Accessibility, Screen Recording, Input Monitoring, Automation, สิทธิ์ administrator หรือรหัสผ่านของผู้ใช้

- เรียกเฉพาะ executable ทางการของ provider จากตำแหน่งที่กำหนดและตรวจลายเซ็นก่อนใช้งาน
- ไม่อ่านไฟล์ OAuth, cookie, database หรือ container ของแอปอื่น
- ไม่บันทึก raw terminal/statusline payload ลงดิสก์
- AGY เป็นผู้เรียก helper ที่อยู่ใน bundle หลังผู้ใช้ตั้งค่าเอง helper ทิ้ง email, workspace, conversation และ field อื่นทันที แล้วเก็บเฉพาะ fraction, reset time, เวอร์ชันและเวลาอ่านค่าใน `agy-quota.json` แบบ `0600`
- helper ของ AGY สืบทอด environment จาก AGY ตามปกติของ process แต่โค้ด helper ไม่อ่านวน ไม่ log และไม่บันทึก environment variable; เฉพาะ probe ของ Codex/Claude ที่ QuotaBar เป็นผู้เรียกเองเท่านั้นที่ได้ minimal allowlisted environment
- เก็บสถานะที่ normalize แล้วใน `status.json`; ไฟล์ทั้งสองอยู่ใน `~/Library/Application Support/QuotaBar/` ซึ่งจำกัดสิทธิ์โฟลเดอร์เป็น `0700`
- ไม่มี analytics, telemetry, automatic installer หรือ server ของ QuotaBar
- เมนู **Check for Updates…** ติดต่อเฉพาะ GitHub Release API สาธารณะเมื่อผู้ใช้กด และไม่ดาวน์โหลดหรือรันโค้ดอัตโนมัติ

Claude Code อาจอัปเดต session/history ของตัวเองเมื่อใช้คำสั่ง `/usage` แต่ข้อมูลส่วนนั้นถูกจัดการโดย CLI ทางการของ Anthropic และ QuotaBar ไม่ได้เปิดอ่านไฟล์ดังกล่าว

อ่าน threat model ฉบับเต็มได้ที่ [SECURITY.md](SECURITY.md)

### ข้อจำกัดปัจจุบัน

- Google ยังไม่มีคำสั่ง/API quota แบบ headless ค่าอัตโนมัติจึงมาจาก statusline callback ขณะ AGY ทำงานเท่านั้น และ field `quota` ยังไม่อยู่ในตาราง schema ที่ Google เผยแพร่ จึงถือเป็น beta ที่อาจต้องปรับตาม AGY รุ่นใหม่
- การเปิด Touch Bar ใน terminal ตรวจจาก process `agy` ที่ signed โดย Google และเป็นลูกหลานของ terminal ด้านหน้า แต่การตรวจเป็นระดับ process tree ของทั้งแอป ดังนั้น AGY ใน tab/window อื่นของ terminal แอปเดียวกันอาจทำให้ QuotaBar แสดงแม้ tab ที่กำลังมองไม่ได้รัน AGY; กรณี `agy` อยู่ใน tmux/server แบบ detached อาจตรวจไม่พบ
- การแสดง Touch Bar ข้ามแอปใช้ private AppKit selector ที่แยกไว้เฉพาะจุด จึงไม่รองรับ Mac App Store และอาจต้องปรับหลัง macOS อัปเดต
- GitHub Release ปัจจุบันเป็น source-only หากจะแจก binary ให้ผู้ใช้ทั่วไปควรใช้ Developer ID signing และ notarization ก่อน

### ถอนการติดตั้ง

ใช้ `/statusline delete` ใน AGY หากเปิด bridge อยู่ ปิด **Launch at Login**, เลือก **Quit QuotaBar** แล้วรัน:

```bash
rm -rf /Applications/QuotaBar.app
rm -rf "$HOME/Library/Application Support/QuotaBar"
rm -rf "$HOME/Library/Caches/com.patrickradulescu.QuotaBar"
```

### สัญญาอนุญาต

MIT © 2026 Patrick Radulescu
