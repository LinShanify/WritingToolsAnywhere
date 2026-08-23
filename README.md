# Writing Tools Anywhere

<img src="Resources/icon-preview.png" width="112" align="right">

Apple Intelligence rewriting in **any** macOS app — including the ones Apple's own
Writing Tools never appears in, like Microsoft Teams, Slack and VS Code.

### **[⬇ Download the latest release](https://github.com/LinShanify/WritingToolsAnywhere/releases/latest)**

macOS 26+ · Apple silicon · signed and notarised, so it opens with no warnings

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
  Uses Apple's translation engine, not a language model.
- **More** — opens an editor panel and brings up **Apple's own Writing Tools**, with
  every tone and summary option Apple ships.

> [!IMPORTANT]
> **Proofread is not Apple's Writing Tools, and doesn't match it.**
>
> It runs on `FoundationModels`, Apple's **general-purpose** on-device base model, driven
> by prompts from this project. Apple's Writing Tools runs **task-trained LoRA adapters**
> that the public API doesn't expose — a different model for proofreading, for each tone,
> for summarising — and edits your text by ranges rather than replacing it wholesale.
>
> So expect Proofread to fix grammar well and go no further. It has no tone options and
> no summarising, because a general model does those badly enough to be worse than not
> offering them. Chinese is weaker than English. **For Apple's own quality, use ✨** —
> that hands the text to the real thing.
>
> The measurements behind all of this: [Quality ceiling](#quality-ceiling-why-inline-cant-match-apple).

A global shortcut (`⌥⌘W`) goes straight to the editor panel, for apps where the bubble
can't read the selection. It can be turned off.

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

### When an app exposes nothing at all

Most apps, native or Electron, will tell the Accessibility API what text is selected.
Some tell it nothing, because they draw their entire interface themselves. WeChat is the
clearest case: walking its accessibility tree finds 215 nodes, of which **209 are the
menu bar**. The main window has three buttons under it and then stops. No focused
element can be obtained at all — not with `AXManualAccessibility`, which wakes up
Electron apps, nor with `AXEnhancedUserInterface`, which VoiceOver uses. There is no
text element to ask, so no amount of asking will help.

That rules out reading the selection, but not the clipboard, and `⌥⌘W` does exactly
that. Replacing still failed though, for a reason worth spelling out: **the editor panel
has to take focus** for Writing Tools to attach to it, WeChat discards its selection the
moment it loses focus, and the paste then lands *beside* the original instead of over
it — leaving both the edit and the text it was meant to replace. No amount of care in
the paste step fixes that; the panel cannot simultaneously take focus and preserve a
selection the app has already thrown away.

The bubble, by contrast, lives in a non-activating panel and never takes focus at all.
So in an app that exposes no text it now appears **on the drag alone**, and the text is
read with a simulated copy only once you choose an action — the clipboard is touched
when you commit to an edit, never on an ordinary click, and the write-back was using it
anyway.

The trigger is "this app returns no focused element", not a list of app names. Anything
else that draws its own interface gets the same treatment without having to be known
about in advance.

The cost is real and worth stating: with no text to check against, a drag that wasn't a
text selection can still raise the bubble.

## Requirements

- macOS 26 or later
- **Apple Intelligence turned on** — checked at launch, with a button that opens the
  right settings pane if it isn't
- Apple silicon
- Command Line Tools only. **Xcode is not required.**

## Install

Download the `.dmg` and drag the app to Applications. The disk image and the app are
both signed with a Developer ID and notarised, so it opens with no warnings.

Updating over an existing copy? macOS won't replace a running app — quit it from the
menu bar first. The in-app update prompt offers to do that for you.

Or build it yourself:

```bash
./setup-signing.sh   # once
./build.sh --run
```

On first launch it asks for **Accessibility** permission: System Settings → Privacy &
Security → Accessibility → enable `WritingToolsAnywhere`. It starts working the moment
you flip the switch — no relaunch needed.

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
| Advanced | Updates | Check GitHub for a new version, automatically or on demand |
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
4. **A structure lock.** Line count and list markers must survive the edit. Asked to
   tidy a three-item checklist, the model collapsed it into one sentence and flipped the
   mood — "fix the timeout issue" came back as "the timeout issue has been fixed",
   turning a list of things to do into a claim they were done. Both are counted, and a
   result that reshaped the text is discarded.
5. **A language lock.** The document's language is identified locally with
   `NLLanguageRecognizer` and named outright in the instructions. Told merely to "write
   in the same language", the model translated Chinese into English in every trial;
   told "the document is written in Chinese, your reply MUST be in Chinese", it stopped.
   The same detector checks the reply, and a result that changed language is discarded —
   the check is deliberately not the model's own judgement.

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
./package.sh                        # dist/*.dmg
./package.sh --notarize <profile>   # also notarise and staple
```

Signing uses a `Developer ID Application` certificate if you have one, otherwise ad-hoc
with a warning. The app and the disk image are both signed and stapled, and the script
then checks the result the way Gatekeeper will — a broken signature fails here rather
than on someone else's Mac.

`<profile>` is a `notarytool` keychain profile, created once with
`xcrun notarytool store-credentials`.

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
- Translation can pick the wrong sense of domain jargon — "standup" came back as a
  standing speech rather than the meeting. It's Apple's engine, so this isn't tunable
  from here; note that it's a wrong word, not an invented fact, which is the difference
  that put translation on this engine rather than the language model.
- Chinese proofreading is weaker than English. It reliably fixes some homophone
  confusions (觉的 → 觉得, 跑的 → 跑得) and misses others (写的 → 写得, 在评估 → 再评估).
  This is the base model's Chinese ability, not something prompting fixes.
- Plain text only — bold, links and other rich formatting are lost.
- "Simulated paste" briefly takes over the clipboard before restoring it. Clipboard
  managers may record that one entry.
- Accessibility permission means the app can't be sandboxed, so it can't ship on the
  Mac App Store.
- Some apps expose no text at all to the Accessibility API — WeChat draws its whole
  window itself, and 209 of its 215 accessibility nodes are the menu bar. There the
  bubble appears on the drag alone and reads the text with a simulated copy once you
  choose an action, so it works, but it can't know whether a drag was really a text
  selection: expect the occasional bubble after dragging something else.
- `⌥⌘W` opens the editor panel, which has to take focus for Writing Tools to attach.
  Apps that drop their selection when they lose focus — WeChat is one — will paste the
  result beside the original instead of over it. Use the bubble in those apps; it never
  takes focus.
- Detecting selections requires a global keyboard and mouse event monitor. Nothing is
  recorded, stored or transmitted unless you deliberately enable the debug log.

## License

MIT
