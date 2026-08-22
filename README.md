# Writing Tools Anywhere

<img src="Resources/icon-preview.png" width="112" align="right">

Apple Intelligence rewriting in **any** macOS app — including the ones Apple's own
Writing Tools never shows up in, like Microsoft Teams, Slack and VS Code.

[中文说明](README.zh-CN.md)

---

## What it does

Select text anywhere, and a small ✨ bubble appears beside it. Hover, and it opens
into a row of one-click actions:

```
┌─────────────────────────────────────────────────────────┐
│ ✓Proofread  ↻Rewrite  ☺Friendly  ▣Professional  ≡Concise  ✨More │
└─────────────────────────────────────────────────────────┘
```

The first five rewrite the text and replace it in place, about a second or two.
The sixth opens an editor panel and brings up Apple's own Writing Tools.

There's also a global shortcut (`⌥⌘W`) that goes straight to the editor panel, for
apps where the bubble can't read the selection.

## How it works

Apple provides no way to inject Writing Tools into another app. Electron apps like
Teams don't use `NSTextView`, so the system never offers Writing Tools there, and
nothing can change that from the outside.

This app takes a different route: read the selection out of whatever app you're in,
run it through Apple Intelligence, and write the result back.

**The one-click actions vs. Apple's panel.** Apple exposes exactly one entry point —
*open* the Writing Tools panel (`showWritingTools:`). There is no API to invoke a
specific tool. So the five quick actions run on **FoundationModels**, the on-device
model framework published in macOS 26 — the same local model Writing Tools uses —
with prompts from this project. Everything stays on device; no network, no API key.

For Apple's own prompts and interface, the sixth chip puts the text into a real
`NSTextView`, which the system will happily attach Writing Tools to.

**Reading the selection.** Global mouse-up and selection keystrokes are watched, then
the selection is read through the Accessibility API. `⌘C` is never simulated here —
hijacking the clipboard on every click would be unacceptable.

Electron apps don't build an accessibility tree until something asks for one, so
`AXManualAccessibility` is set on them first. That's what makes Teams, Slack, VS Code
and Obsidian report their selection at all.

## Requirements

- macOS 26 or later (the quick actions need FoundationModels)
- **Apple Intelligence turned on** — checked at launch, with a button that takes you
  to the right settings pane if it isn't
- Apple silicon
- Command Line Tools only. **Xcode is not required.**

## Install

### From a release

Download the `.dmg`, drag the app to Applications, then — because the app isn't
notarised yet — clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/WritingToolsAnywhere.app
```

### From source

```bash
./setup-signing.sh   # once: creates a stable local signing identity
./build.sh --run
```

On first launch it asks for **Accessibility** permission:
System Settings → Privacy & Security → Accessibility → enable
`WritingToolsAnywhere`, then relaunch.

#### Why `setup-signing.sh` exists

macOS ties Accessibility permission to an app's **code signature**, not to its path or
bundle ID.

An ad-hoc signature is derived from the binary's contents, so **every rebuild produces
a new identity** and silently invalidates the permission you already granted — while
the System Settings toggle stays on. The result is the worst possible failure mode:
it looks authorised, it isn't, and macOS never prompts again.

`setup-signing.sh` creates a self-signed certificate in your login keychain so the
signing identity stops changing. Grant Accessibility once and it survives rebuilds,
and even moving the folder.

## Settings

Menu bar ✨ → **Settings…** (`⌘,`)

| Section | Item | Notes |
|---|---|---|
| Status | Apple Intelligence | Live check, with a jump to the settings pane |
| Status | Accessibility | Live check, with a jump to the settings pane |
| General | Start at login | `SMAppService`, no helper bundle |
| General | Bubble | Turn it off to use the shortcut only |
| General | Shortcut | Modifier checkboxes + key menu, applied immediately |
| Language | Interface | System / 简体中文 / English |
| Language | Rewrite in | Match the input, or force 中文 / English / 日本語 / 한국어 / Français / Deutsch / Español |
| Advanced | Auto-replace | Write back as soon as Writing Tools finishes |
| Advanced | Replace using | Simulated paste (most compatible) or Accessibility |
| Advanced | Clipboard | Restore the previous contents afterwards |
| Advanced | Debug log | **Off by default** — it records the text you select |

Interface language and rewrite language are independent, so you can keep an English
interface and have drafts rewritten into Chinese, or the other way round.

Settings live in `~/Library/Application Support/WritingToolsAnywhere/config.json`.

## Shortcuts

| Where | Key | Action |
|---|---|---|
| Anywhere | select text | The bubble appears; hover to expand |
| Anywhere | `⌥⌘W` | Capture the selection and open the editor panel |
| Editor | `⌘J` | Reopen Writing Tools |
| Editor | `⌘↩` | Replace the original text |
| Editor | `⇧⌘C` | Copy the result |
| Editor | `esc` | Cancel |

## Building a release

```bash
./package.sh                  # build, sign, and produce dist/*.dmg
./package.sh --notarize WTA   # also notarise and staple
```

Signing is picked automatically: a `Developer ID Application` certificate if you have
one (hardened runtime + secure timestamp, ready to notarise), otherwise ad-hoc with a
printed warning. The local development certificate is deliberately never used for
distribution — it's trusted only on the machine that created it.

To notarise you need an Apple Developer account, then once:

```bash
xcrun notarytool store-credentials WTA \
    --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD
```

## Project layout

| Path | Purpose |
|---|---|
| `Sources/AppDelegate.swift` | Menu bar, onboarding, coordination |
| `Sources/SettingsWindow.swift` | Settings window |
| `Sources/SelectionWatcher.swift` | Global selection detection and bubble placement |
| `Sources/BubbleController.swift` | The bubble's non-activating panel |
| `Sources/ActionMenuView.swift` | The expanded row of chips (custom-drawn) |
| `Sources/PanelController.swift` | Editor panel and the `showWritingTools:` call |
| `Sources/TextBridge.swift` | Cross-app selection reading, write-back, clipboard safety |
| `Sources/LLM.swift` | FoundationModels wrapper and prompts |
| `Sources/HotKey.swift` | Carbon global hotkey (needs no extra permission) |
| `Sources/LoginItem.swift` | Start at login |
| `Sources/L10n.swift` | English / Chinese interface |
| `Sources/MenuBarIcon.swift` | Menu bar glyph, drawn in code |
| `tools/MakeIcon/main.swift` | App icon, drawn with Core Graphics at every size |

## Known limitations

- Plain text only — bold, links and other rich formatting are lost.
- "Simulated paste" briefly takes over the clipboard before restoring it. Clipboard
  managers may record that one entry.
- Accessibility permission means the app can't be sandboxed, so it can't ship on the
  Mac App Store.
- The bubble depends on apps reporting their selection over the Accessibility API.
  Most native and Electron apps do; a few (some Java apps, games, custom text engines,
  remote desktops) don't. Use `⌥⌘W` there — it falls back to `⌘C`.
- Bubble placement prefers the selection's screen rectangle; some apps return `0×0`,
  in which case it falls back to the pointer position.
- Detecting selections requires a global keyboard and mouse event monitor. Nothing is
  recorded, stored or transmitted unless you deliberately enable the debug log.

## License

MIT
