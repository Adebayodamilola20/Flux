# DevNotch

A minimal macOS utility that watches how much of your AI model quota you have
used — at a glance, without opening a browser.

DevNotch lives as a slim rail against the edge of your screen. At rest it is a
7&nbsp;px sliver; hover it and it expands into a column of rings, one per AI
tool; focus a ring and a card shows the window, the percentage, and where the
figure came from.

> **Status** — the rail has **three slots**, and you choose which of **seven**
> integrations fill them. None of them requires a sign-in of DevNotch's own:
> each reads a tool already installed and authenticated on this Mac.
>
> | Integration | Figure shown | Where it comes from | Grade |
> | --- | --- | --- | --- |
> | **Claude** | Session and weekly utilisation | Live from Anthropic | API |
> | **Codex** | Codex allowance on your ChatGPT plan | The last figure OpenAI reported, recorded by Codex locally | Local |
> | **OpenCode** | Tokens used by the current model | The session store OpenCode keeps on this Mac | Local |
> | **Kilo Code** | Tokens used by the current model | The same session store (Kilo is an OpenCode fork) | Local |
> | **Antigravity** | Weekly limit per model group | The `agy /usage` panel, driven under a pseudo-terminal | CLI |
> | **Hermes** | Tokens used by the current model | Its own insights command | Local |
> | **OpenRouter** | Credits and rate limit | Official usage API | API |
>
> The **grade** is not decoration — it is shown in the app. An API reading
> outranks a local record, which outranks a figure parsed out of a CLI panel.

---

## What it does

DevNotch tracks one **usage window** per tool and draws it as a coloured ring:

- **Percent used** — how close you are to the window's limit, on the ring and
  optionally in the menu bar. Green under 45%, lime to 70%, orange past it.
- **Working / idle / waiting** — a live hint of what a local session is doing.
- **Current session & all-models windows** — with reset times where known.
- **Local history** — snapshots kept on disk, so the detail view can draw a
  sparkline over time.
- **Settings** — rail edge (left/right), offset, monitor, auto-collapse,
  refresh interval, optional menu-bar icon/percent, launch at login.
- **Privacy first** — AI usage is a sensitive number, so the figures come only
  from sources you already own.

### The Claude slot

Claude usage is assembled from several sources, in order of freshness:

1. **A live reading from Anthropic** — the figure `claude /usage` shows, fetched
   now. This uses the session Claude Code has already established on this Mac,
   read from the **login Keychain**. macOS asks you to approve that read the
   first time, because the item belongs to Claude Code rather than to DevNotch;
   choose **Always Allow** and the rail tracks the CLI to the second.
2. **Claude Code's cached figure** (`~/.claude.json`) — Anthropic's own numbers,
   but only as fresh as the last time Claude Code talked to the API. Used when
   the live reading is unavailable, and always labelled with its age.
3. **Anthropic Admin API** (optional) — organisation API consumption, from an
   Admin API key you create and paste. Stored in the **macOS Keychain**, never
   in a file.
4. **Local Claude Code transcripts** — the token counts your sessions actually
   generated, measured against a **budget you configure**.

Two things about the Keychain read are worth stating plainly. The token is used
for exactly one request — Anthropic's own usage endpoint, for your own account —
and is never stored, logged, or sent anywhere else. And it is only ever *read*,
never refreshed: refreshing would rotate the token and sign you out of your own
CLI, so when it expires DevNotch falls back to the cached figure instead.

DevNotch does **not** scrape the Claude web app, read browser cookies, or write
to Claude Code's credential store.

### The Codex slot

OpenAI reports the Codex allowance on a ChatGPT plan in the reply to a model
request, and nowhere else — there is no endpoint to ask. Codex records each
figure in its session transcript, so DevNotch reads the newest one and refreshes
the moment Codex writes another. Polling for a fresher number would mean sending
a prompt — spending the allowance in order to measure it — so the card states
how old the reading is instead.

The slot is named for the tool rather than the account, because the tool is what
moves the number: chat messages in ChatGPT have no local record and never appear
here. An optional API key adds **API spend**, a separate billing account, shown
as its own window rather than conflated with the plan allowance.

### The OpenCode, Kilo Code and Hermes slots

These read a record the tool already keeps on this Mac — OpenCode and Kilo Code
share a session store (Kilo is a fork), Hermes reports through its own insights
command. Each shows tokens used by whichever model you are currently on. No
sign-in, no key.

These are **local arithmetic, not a provider-reported quota** — useful for
tracking your own spend, and labelled as such rather than dressed up as an
official figure.

### The Antigravity slot

Antigravity publishes no quota API and caches nothing to disk. Its weekly limit
exists in exactly one place a user can reach: the `/usage` panel in its own CLI.
DevNotch drives `agy` under a pseudo-terminal, types `/usage`, and reads what it
drew. The CLI signs itself in exactly as it would for you at a terminal —
DevNotch never sees its credentials.

The CLI runs in `~/.flux/cli-probe` (the path still carries the project's
earlier name), an empty directory kept for the purpose. These tools treat their
working directory as a workspace and index it,
and an app launched from Finder has `/` as its working directory — pointed at
the filesystem root, `agy` spends so long starting that the usage command never
lands. You will be asked to trust that folder once, by the CLI itself.

That is a rendered panel, not an API contract, so these figures are labelled
**CLI-derived** and ranked below an API reading. A probe takes about half a
minute and starts a real process, so results are cached and the CLI is never
driven on the refresh timer.

### The OpenRouter slot

The one integration built on an official usage API: a single call returns spend
and limit together. It is the proof that the generic pipeline can put a real
percentage on the rail without a CLI, a scrape, or an estimate. It needs a key,
which you create at openrouter.ai.

## Why it's useful

- **Know before you're cut off.** A rolling session window can hit its limit
  mid-task. DevNotch keeps that number on screen so you aren't surprised
  mid-prompt.
- **At a glance.** Percent rings are readable from across the room.
- **One rail for every tool** — with the provenance stated rather than
  flattened away.

## Trade-offs

- **Freshness differs by provider, and the card says which.** Claude is live to
  the second. Codex is as fresh as the last time you ran Codex. Antigravity is
  a cached CLI panel. None is presented as more current than it is.
- **A CLI panel is not an API.** A layout change in Antigravity's CLI can make
  it unreadable, which is why it is ranked last.
- **Local tracking is arithmetic, not an official count.**
- **Deliberately conservative.** DevNotch will show "usage unavailable", with
  the reason, rather than fill a gap with arithmetic that could be read as an
  official figure.
- **Three slots, not an open marketplace.** The rail is sized and laid out
  around exactly three rings. Adding a provider is a deliberate, first-class
  integration, not a generic adapter.
- **Keychain prompts.** Reading Claude Code's session raises a macOS approval
  dialog the first time. Declining is respected: DevNotch falls back to the
  cached figure and does not ask again for half an hour.
- **macOS-only.** The rail window, the status item and the Keychain access are
  AppKit. There is no Windows or Linux build.

## Requirements

- macOS 11 or later
- [Flutter](https://docs.flutter.dev/get-started/install/macos) (SDK `^3.12.0`)
- Xcode, for the native macOS runner

## Getting started

```sh
git clone https://github.com/Adebayodamilola20/Flux.git devnotch
cd devnotch
flutter pub get
flutter run -d macos
```

> The repository is still named `Flux` (the project's earlier name). Renaming it
> on GitHub is safe — old clone URLs keep redirecting — but update
> `web/src/config/site.ts` afterwards, which is the one place the site reads it
> from.

On first launch there is **nothing to connect**. DevNotch looks for the tools
you already have and turns on a slot for each one it finds. No sign-in, no
consent screen, no API key. Those tools are already authenticated, and for these
providers an account token carries no quota anyway.

Claude will ask macOS once for permission to read Claude Code's stored session —
choose **Always Allow** for live figures.

Switching a slot off is remembered. Two slots also accept an optional API key
(**Add API key** / **Add admin key**) which adds a *separate* figure — API spend
for Codex, organisation usage for Claude. Neither is needed for the plan
allowance.

## Testing

```sh
flutter test
```

The architecture is designed to be tested with fakes: there is a `NativeBridge`
seam plus fake providers and a fake native bridge under `test/support/`, so the
controller, providers, and services run without a real macOS side.

## Architecture

DevNotch keeps every macOS-platform detail behind one seam
(`lib/services/native/native_bridge.dart`), so the Dart layers never import a
platform channel directly.

```
lib/
  app.dart                # composition root + surface router
  main.dart               # object-graph wiring
  core/                   # formatting, logging
  models/                 # provider-agnostic data (usage, windows, sessions)
  providers/
    claude/               # Keychain session, admin API, local transcripts
    chatgpt/              # Codex allowance, read from its session record
    agent/                # OpenCode, Kilo Code, Hermes
    antigravity/          # the `agy /usage` panel, under a pty
    api/                  # key-based providers (OpenRouter, ChatGPT API spend)
    cli/                  # shared CLI-panel parsing
    provider_catalog.dart # the 7 integrations + slotCount
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
web/                      # the marketing + download site (Astro, static)
```

Key ideas:

- **Provider-agnostic UI.** No widget knows what "Claude" is; they all consume
  provider-agnostic `UsageData`. Adding a provider is one line in `main.dart`
  plus its implementation.
- **Single window, several surfaces.** Flutter owns one view; the shell switches
  it between rail / onboarding / settings / detail.
- **Honest states.** Every slot renders from the first frame, including empty
  ones, so the rail never hints a provider is connected when it is not.
- **Local scans on a background isolate**, so the UI stays smooth.
- **Security** — secrets in the Keychain, browser-based auth for the Admin API,
  no browser scraping, no reading terminal contents.

## Website

The marketing and download site lives in [`web/`](web/) — a static Astro build.

```sh
cd web
npm install
npm run dev
```

`web/src/config/site.ts` is the single source of product facts for the site:
name, version, repository URLs, integrations, features and FAQ. Publishing a
release means setting `url` and `available: true` on the macOS entry there.

## License

[MIT](LICENSE) © Stephen Adebayo
