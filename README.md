# Flux

A minimal macOS menu-bar utility that watches how much of your AI model quota
you have used and how busy your local AI sessions are — at a glance, without
opening a browser.

Flux started as *ai_usage_monitor*. It lives as a slim transparent rail against
the edge of your screen. At rest it is a coloured sliver; hover over it and it
expands into a column of rings, one per AI tool; focus a ring and a card shows
the window, the percentage, and hint of whether the session is working.

> **Status**: version one ships a fully implemented **Claude** slot. **Codex**
> and **Google Antigravity** slots are reserved (their rings render, but they
> are not yet implemented) — see [Architecture](#architecture).

---

## What it does

Flux tracks one **usage window** per AI provider and shows it as a coloured
ring:

- **Percent used** — how close you are to the window's limit, on the ring and
  in the menu bar.
- **Working / idle / waiting** — a live hint of what a local session is doing.
- **Current session & all-models windows** — with reset times where known.
- **Local history** — snapshots kept on disk so the detail view can draw a
  sparkline over time.
- **Settings** — rail edge (left/right), offset, monitor, auto-collapse,
  refresh interval, optional menu-bar icon/percent, launch at login.
- **Privacy first** — AI usage is a sensitive number, so the figures come only
  from sources you own or sign into.

### The Claude slot

Claude usage is assembled from two *legitimate* sources, in order of authority:

1. **Anthropic Admin API** (provider-reported) — the only public, supported
   endpoint for account-level Claude usage. Your Admin API key is stored in the
   **macOS Keychain**, never in a file. The figure it reports is what Anthropic
   says the account consumed.
2. **Local Claude Code transcripts** (this Mac) — the token counts your Claude
   Code sessions actually generated, measured against a **user-configured
   budget**, so you can track your own spend.

Flux does **not** scrape the Claude web app, call undocumented endpoints, read
browser cookies, or touch Claude Code's own credential store.

## Why it's useful

- **Know before you're cut off.** A rolling 5-hour Claude session window can
  hit its limit mid-task. Flux keeps that number on screen and in the menu bar
  so you aren't surprised mid-prompt.
- **At a glance.** Percent rings are readable from across the room — no need to
  open the console.
- **One rail for every tool.** The slot model means Codex and Antigravity drop
  into the same rail as soon as their integrations land, with identical
  behaviour.
- **Budgeting that actually tracks local work.** Claude Code's own token counts
  against a budget you set, so heavy days are visible even without an admin key.

## Trade-offs

- **Claude use reports a *number*, but not the answer to "how many free
  requests do I have left?"** The Admin API reports consumption. Trial/
  subscription limits are not exposed, so percentage reflects use against a
  window you define, not an official "requests remaining" figure.
- **Local tracking is arithmetic, not an official count.** Token totals from
  transcripts are this app's calculation against your budget — useful for
  tracking your own spend, but not a provider-reported quota.
- **Deliberately conservative about numbers.** Flux will happily show "not
  connected" rather than fill a gap with local arithmetic that could be read as
  official usage. Accuracy of *meaning* beats maximising what's on screen.
- **Three fixed slots, not an open marketplace.** The rail is sized and laid
  out around exactly three rings. Adding a provider is a deliberate,
  first-class integration, not a generic adapter — great for quality, slower to
  add tools.
- **Keychain requirement.** The Claude Admin API key must live in the macOS
  Keychain; if it is removed there, the stored connection is downgraded to
  "not connected" until you re-add it.
- **macOS-only.** This is a menu-bar / edge-window app written for macOS. It is
  not a mobile or cross-platform build.

## Requirements

- macOS
- [Flutter](https://docs.flutter.dev/get-started/install/macos) (SDK `^3.12.0`)
- Xcode (for the native macOS runner)

## Getting started

```sh
git clone <your-repo-url> flux
cd flux
flutter pub get
flutter run -d macos
```

On first launch Flux opens the **Connect** panel. For Claude:

1. Click **Connect** — it opens [your Anthropic admin keys
   page](https://console.anthropic.com/settings/admin-keys) in your browser.
2. Create an Admin API key and paste it back.
3. The key is verified against the real API, then stored in your Keychain.

You can also set **token budgets** for local tracking in Settings, which lets
Flux count Claude Code session output against a plan of your own.

## Testing

```sh
flutter test
```

The architecture is designed to be tested with fakes: there is a `NativeBridge`
seam plus fake providers and a fake native bridge under `test/support/`, so the
controller, providers, and services run without a real macOS side.

## Architecture

Flux keeps every macOS-platform detail behind one seam
(`lib/services/native/native_bridge.dart`), so the Dart layers never import a
platform or method channel directly.

```
lib/
  app.dart                # composition root + surface router
  main.dart               # object-graph wiring
  core/                   # formatting, logging
  models/                 # provider-agnostic data (usage, windows, sessions)
  providers/
    claude/               # the only implemented slot
    provider_catalog.dart # the 3 slots (claude, codex, antigravity)
  services/
    native/               # NativeBridge — the single macOS seam
    usage_controller.dart # fetch scheduling + state
    shell_controller.dart # window/rail placement + surface routing
  ui/
    rail/                 # the edge widget (rings, callouts)
    panel/                # onboarding, settings, provider detail
    theme/ widgets/       # rings, bars, sparklines, glyphs
macos/                    # Swift/AppKit runner (rail window, status item,
                          # keychain, process scanning, login item)
```

Key ideas:

- **Provider-agnostic UI.** No widget knows what "Claude" is; they all consume
  provider-agnostic `UsageData`. Adding a provider is one line in
  `main.dart` plus its implementation.
- **Single window, several surfaces.** Flutter owns one view; the shell
  switches it between rail / onboarding / settings / detail.
- **Honest states.** Every slot renders from the first frame, including reserved
  (unimplemented) ones, so the rail never hints a provider is connected when it
  is not.
- **Local scans on a background isolate**, so the UI stays smooth.
- **Security:** secrets in the Keychain, browser-based auth for the Admin API,
  no browser scraping, no reading terminal contents.

## License

[MIT](LICENSE) © Stephen Adebayo
