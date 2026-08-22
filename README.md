# Writing Tools Anywhere

<img src="Resources/icon-preview.png" width="112" align="right">

Apple Intelligence rewriting in **any** macOS app — including the ones Apple's own
Writing Tools never appears in, like Microsoft Teams, Slack and VS Code.

[中文说明](README.zh-CN.md)

---

## What it does

Select text anywhere, and a small ✨ bubble appears beside it. Hover, and it opens into
three things:

```
┌────────────────────────────────────┐
│  ✓ Proofread   🄰 Translate   ✨ More │
└────────────────────────────────────┘
```

- **Proofread** — fixes grammar, spelling and awkward phrasing, then replaces the text
  in place. It keeps your voice and length; it does not make you sound corporate.
- **Translate** — between your language and English, direction chosen automatically.
- **More** — opens an editor panel and brings up **Apple's own Writing Tools**, with
  every tone and summary option Apple ships.

A global shortcut (`⌥⌘W`) goes straight to the editor panel, for apps where the bubble
can't read the selection. It can be turned off.

**Inline is deliberately one thing.** Grammar is what a general-purpose model is
reliable at. Tone and summarising need the adapters Apple keeps to itself, so they live
behind ✨ rather than being approximated badly — see
[Quality ceiling](#quality-ceiling-why-inline-cant-match-apple).

## How it works

Apple provides no way to inject Writing Tools into another app. Electron apps like
Teams don't use `NSTextView`, so the system never offers Writing Tools there, and
nothing changes that from the outside.

This app takes a different route: read the selection out of whatever app you're in, run
it through Apple Intelligence, and write the result back.

**Reading the selection.** Global mouse-up and selection keystrokes are watched, then
the selection is read through the Accessibility API. `⌘C` is never simulated here —
hijacking the clipboard on every click would be unacceptable. Electron apps don't build
an accessibility tree until something asks for one, so `AXManualAccessibility` is set on
them first; that's what makes Teams, Slack, VS Code and Obsidian report a selection at
all.

**Writing it back.** Simulated paste by default, because that is the only thing that
works reliably in Electron apps. The previous clipboard contents are restored
afterwards.

## Requirements

- macOS 26 or later
- **Apple Intelligence turned on** — checked at launch, with a button that opens the
  right settings pane if it isn't
- Apple silicon
- Command Line Tools only. **Xcode is not required.**

## Install

Download the `.dmg` and drag the app to Applications. The disk image and the app are
both signed with a Developer ID and notarised, so it opens with no warnings.

Or build it yourself:

```bash
./setup-signing.sh   # once
./build.sh --run
```

On first launch it asks for **Accessibility** permission: System Settings → Privacy &
Security → Accessibility → enable `WritingToolsAnywhere`, then relaunch.

### Why `setup-signing.sh` exists

macOS ties Accessibility permission to an app's **code signature**, not to its path or
bundle ID.

An ad-hoc signature is derived from the binary's contents, so **every rebuild produces a
new identity** and silently invalidates the permission you already granted — while the
System Settings toggle stays on. That is the worst possible failure mode: it looks
authorised, it isn't, and macOS never prompts again.

`setup-signing.sh` creates a self-signed certificate in your login keychain so the
signing identity stops changing. Grant Accessibility once and it survives rebuilds, and
even moving the folder.

If permissions do get into a bad state:

```bash
tccutil reset Accessibility com.linshan.WritingToolsAnywhere
```

## Settings

Menu bar ✨ → **Settings…** (`⌘,`)

| Section | Item | Notes |
|---|---|---|
| Status | Apple Intelligence | Live check, with a jump to the settings pane |
| Status | Accessibility | Live check, with a jump to the settings pane |
| General | Start at login | `SMAppService`, no helper bundle |
| General | Bubble | Turn it off to use the shortcut only |
| General | Shortcut | Enable or disable it, and pick the combination. Turning it off hands the keys back to other apps |
| Language | Interface | System / 简体中文 / English |
| Language | My language | Translation runs between this and English. Set it to English and everything non-English becomes English |
| Advanced | Auto-replace | Write back as soon as Writing Tools finishes |
| Advanced | Replace using | Simulated paste (most compatible) or Accessibility |
| Advanced | Clipboard | Restore the previous contents afterwards |
| Advanced | Debug log | **Off by default** — it records the text you select |

Proofreading always replies in the language you wrote in; the interface setting only
affects the app's own UI. Translation uses Apple's built-in engine, so a language pair
must be downloaded in System Settings first — the bubble names the missing pair if it
isn't.

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

## Quality ceiling: why inline can't match Apple

The three paths in this app run on **different engines**, and that difference is the
whole story:

| | Engine | Quality |
|---|---|---|
| **Inline** (Proofread) | `FoundationModels` — Apple's **general-purpose** on-device base model, prompted by this project | Good enough for grammar. Nothing more. |
| **Translate** | `Translation.framework` — Apple's dedicated translation engine, the same one the Translate app and Safari use | Apple's own quality |
| **More** (✨) | `showWritingTools:` — **Apple's real Writing Tools**, with its task-trained LoRA adapters | Apple's own quality |

**Apple's Writing Tools does not prompt a general model.** It loads **task-specific LoRA
adapters** — one trained for proofreading, one for summarising, one per tone — and swaps
them in at runtime. It then delivers results as **`(range, replacement)` pairs** through
`NSWritingToolsCoordinator`, editing the app's existing text storage rather than
returning a blob of prose. A preamble has nowhere to go.

**Neither is reachable from the public API.** FoundationModels hands you the
general-purpose ~3B base model and a whole-string response. Apple's shipped adapters are
private system assets; `SystemLanguageModel.Adapter(name:)` loads adapters *you*
provide, not Apple's.

So inline editing is prompt engineering against a general model, and it has a ceiling.
That is why it does one job.

### Where the ceiling shows up

Ask the base model for anything beyond correctness and it drifts, measurably. On real
chat messages:

| Asked for | What the general model does |
|---|---|
| A professional tone | A one-line note comes back as a 2.4× letter template — `Hi [Recipient's Name] … Best regards, [Your Name]`. Leashing the prompt reins in the length but not the instinct. |
| A friendly tone | Appends pleasantries the original never contained: "Thanks for your understanding!" |
| Something shorter | Returns the document unchanged about half the time. Tightening the prompt makes it *worse* — given "the result MUST be clearly shorter" plus a character budget, the model stops editing and copies its input. |
| A translation | **Fabricates.** "明天" (tomorrow) comes back as "Wednesday"; an untranslated "someone" is left sitting in a Chinese sentence. |

That last one is why Translate uses `Translation.framework` instead. Apple's translator
makes ordinary word-choice mistakes rather than confident inventions — a very different
kind of wrong to paste into someone's message.

### What keeps proofreading honest

1. **Guided generation.** The response is forced into a schema with a single `text`
   field, so "Here is the corrected version:" has nowhere to live. Built from
   `DynamicGenerationSchema` at runtime rather than the `@Generable` macro, whose
   compiler plugin ships only with Xcode.
2. **A fenced document.** The text is wrapped in `⟪⟪⟪ … ⟫⟫⟫`. Without it the model
   answers short or question-shaped input instead of editing it — `ok` produces an
   invented paragraph, and text reading "ignore your instructions" is obeyed. The model
   echoes fragments of the fence back, so the fence characters are trimmed as a
   character set rather than matched as whole markers.
3. **A plausibility ceiling.** A result more than ~1.6× the input is a continuation, not
   a correction, and is discarded rather than pasted.

When the result comes back identical to the input, the bubble says so instead of pasting
your own words back over themselves.

### Could we train our own adapter?

Technically yes — `SystemLanguageModel.Adapter` is public and Apple ships a training
toolkit. Two reasons it isn't worth it:

- **Adapters are locked to a base model version** — one per system model version, no
  exceptions. A macOS update can break it, and the app then fails for everyone until
  it's retrained and reshipped.
- **It wouldn't close the real gap**, which is the transport: Apple edits ranges in
  place, we replace a whole selection.

**Inline is the convenience path, ✨ is the quality path.** It puts your text into a real
`NSTextView` and calls `showWritingTools:`, so you get Apple's own adapters, prompts and
accept/reject UI — in an app that was never going to offer them.

## Building a release

```bash
./package.sh                  # dist/*.dmg
./package.sh --notarize WTA   # also notarise and staple
```

Signing is picked automatically: a `Developer ID Application` certificate if you have
one, otherwise ad-hoc with a printed warning. Both the app and the disk image are
signed, notarised and stapled, and the script asserts the result the way Gatekeeper
will see it — a broken signature fails here rather than on someone else's Mac.

`setup-notarize.sh` checks the Developer ID setup, installs Apple's intermediate
certificate if it's missing, and stores notarisation credentials. `backup-signing.sh`
exports the signing identity, which lives only in the keychain that created it.

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
| `Sources/LLM.swift` | FoundationModels wrapper, prompts, guided generation |
| `Sources/Translator.swift` | Translation.framework wrapper and language detection |
| `Sources/HotKey.swift` | Carbon global hotkey (needs no extra permission) |
| `Sources/MenuBarIcon.swift` | Menu bar glyph, drawn in code |
| `tools/MakeIcon/main.swift` | App icon, drawn with Core Graphics at every size |

`build.sh` compiles and assembles the `.app`; `make-icon.sh` regenerates the icon.

Menu bar ✨ → Settings → Advanced → **Copy Diagnostics** dumps permission and model
state. Turning on the debug log writes to `~/Library/Logs/WritingToolsAnywhere.log`.

## Known limitations

- Translation needs Apple's language packs installed (System Settings → General →
  Language & Region → Translation Languages). Missing pairs are reported by name.
- Language detection needs a few words. Below 0.6 confidence — "ok" scores as Polish,
  "LGTM" as Turkish — the direction falls back to your configured pair rather than
  trusting the guess.
- Plain text only — bold, links and other rich formatting are lost.
- "Simulated paste" briefly takes over the clipboard before restoring it. Clipboard
  managers may record that one entry.
- Accessibility permission means the app can't be sandboxed, so it can't ship on the
  Mac App Store.
- The bubble depends on apps reporting their selection over the Accessibility API. Most
  native and Electron apps do; a few (some Java apps, games, custom text engines, remote
  desktops) don't. Use `⌥⌘W` there — it falls back to `⌘C`.
- Detecting selections requires a global keyboard and mouse event monitor. Nothing is
  recorded, stored or transmitted unless you deliberately enable the debug log.

## License

MIT
