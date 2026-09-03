/**
 * Every product fact the site states, in one place.
 *
 * Nothing below is invented. Provider names, taglines and accent colours are
 * transcribed from `lib/providers/provider_catalog.dart`; palette values and
 * notch metrics from `lib/ui/theme/app_theme.dart` and `macos/Runner/
 * RailMetrics.swift`. If the app changes, change it here — no component
 * hard-codes a product detail.
 */

export const PRODUCT = {
  name: 'DevNotch',
  /** Two words, the way the feature labels are. */
  category: 'AI usage, on the edge of your Mac',
  /** Broken across lines in the hero, deliberately. */
  /** Line two's last word gets the highlighter swipe. */
  headline: { line1: 'Your AI usage.', line2: 'Always in ', mark: 'view' },
  /**
   * One sentence. The hero does not explain — the demo does.
   */
  description:
    'A notch that lives on the edge of your screen and shows how much of each AI quota you have left. Reads the tools already on your Mac. Nothing to sign in to.',
  version: '1.0.0',
  /** From the app's own platform support: only `macos/` exists. */
  platforms: 'macOS 11 or later',
  /** The bare floor, for the "Minimum …" line on the download card. */
  minOS: 'macOS 11',
  license: 'MIT',
  author: 'Stephen Adebayo',
} as const;

/** The one place the repository lives. */
export const GITHUB = {
  owner: 'Adebayodamilola20',
  repo: 'Flux',
  url: 'https://github.com/Adebayodamilola20/Flux',
  issuesUrl: 'https://github.com/Adebayodamilola20/Flux/issues',
  releasesUrl: 'https://github.com/Adebayodamilola20/Flux/releases',
  licenseUrl: 'https://github.com/Adebayodamilola20/Flux/blob/main/LICENSE',
  readmeUrl: 'https://github.com/Adebayodamilola20/Flux#readme',
} as const;

/**
 * Download targets.
 *
 * `url: null` renders the platform as unavailable rather than as a dead link.
 * When a release is published, set `url` to the asset and flip `available`.
 */
export interface DownloadTarget {
  id: 'macos' | 'windows';
  label: string;
  detail: string;
  /** Null until a real artefact exists. Never point this at a placeholder. */
  url: string | null;
  /** Is there a build to download right now? */
  available: boolean;
  /**
   * Does the app run on this platform at all? Distinct from [available]: macOS
   * is supported with no release cut yet, Windows is not supported.
   */
  supported: boolean;
  /** Short status, shown as a chip beside the platform name. */
  status: string;
  note: string;
  /** Where to send someone while `url` is null, or null for no link. */
  watch: { label: string; url: string } | null;
}

export const DOWNLOADS: DownloadTarget[] = [
  {
    id: 'macos',
    label: 'macOS',
    detail: 'Apple silicon & Intel',
    url: null,
    available: false,
    supported: true,
    status: 'Release pending',
    note: 'The app is built and runs — no binary has been published yet. Run it from source below.',
    watch: { label: 'Watch for the first release', url: GITHUB.releasesUrl },
  },
  {
    id: 'windows',
    label: 'Windows',
    detail: 'Not supported',
    url: null,
    available: false,
    supported: false,
    status: 'macOS-only',
    note: 'The notch and menu-bar item are built on AppKit, so there is no Windows build.',
    watch: null,
  },
];

export const PRIMARY_DOWNLOAD = DOWNLOADS[0]!;

export const BUILD_FROM_SOURCE = [
  `git clone ${GITHUB.url}.git devnotch`,
  'cd devnotch',
  'flutter pub get',
  'flutter run -d macos',
] as const;

/**
 * The integrations that exist in `ProviderCatalog.available`, in catalogue
 * order. `accent` is the descriptor's own colour, as an sRGB hex.
 */
export interface Integration {
  id: string;
  name: string;
  tagline: string;
  accent: string;
  /** How the figure is obtained — stated because the app states it. */
  source: string;
  /** Whether the reading comes from an API, a local file, or a CLI panel. */
  grade: 'API' | 'Local' | 'CLI';
}

export const INTEGRATIONS: Integration[] = [
  {
    id: 'claude',
    name: 'Claude',
    tagline: 'Subscription usage and Claude Code activity',
    accent: '#D97757',
    source: 'Live from Anthropic',
    grade: 'API',
  },
  {
    id: 'chatgpt',
    name: 'Codex',
    tagline: 'Codex allowance on your ChatGPT plan',
    accent: '#10A37F',
    source: 'Recorded locally by Codex',
    grade: 'Local',
  },
  {
    id: 'opencode',
    name: 'OpenCode',
    tagline: 'Tokens used by the model OpenCode is on',
    accent: '#8E8E96',
    source: 'Local session store',
    grade: 'Local',
  },
  {
    id: 'kilocode',
    name: 'Kilo Code',
    tagline: 'Tokens used by the model Kilo Code is on',
    accent: '#7C5CFF',
    source: 'Local session store',
    grade: 'Local',
  },
  {
    id: 'antigravity',
    name: 'Antigravity',
    tagline: 'Weekly model limits from the Antigravity CLI',
    accent: '#4285F4',
    source: 'CLI usage panel',
    grade: 'CLI',
  },
  {
    id: 'hermes',
    name: 'Hermes',
    tagline: 'Tokens used by the model Hermes is on',
    accent: '#E0A458',
    source: 'Its own insights command',
    grade: 'Local',
  },
  {
    id: 'openrouter',
    name: 'OpenRouter',
    tagline: 'Credits and rate limit from your OpenRouter key',
    accent: '#6467F2',
    source: 'Official usage API',
    grade: 'API',
  },
];

/** `ProviderCatalog.slotCount` — how many rings the notch is laid out for. */
export const SLOT_COUNT = 3;

/**
 * Eight tiles, two-word labels. Each one is shipped behaviour — nothing here
 * describes something the app cannot do.
 */
export interface Feature {
  /** Two lines, as the reference sets them. No body copy — the label is it. */
  label: [string, string];
  /** Which mark the tile draws. */
  art:
    | 'rings'
    | 'sliver'
    | 'menubar'
    | 'spark'
    | 'grade'
    | 'key'
    | 'edges'
    | 'swift';
  /** One item gets the hand-drawn ring, the way the reference marks one. */
  circled?: boolean;
}

export const FEATURES: Feature[] = [
  { label: ['Three', 'rings'], art: 'rings' },
  { label: ['Persistent', 'sliver'], art: 'sliver' },
  { label: ['Menu bar', 'readout'], art: 'menubar' },
  { label: ['Local', 'history'], art: 'spark' },
  { label: ['Stated', 'provenance'], art: 'grade' },
  { label: ['Nothing to', 'sign in to'], art: 'key' },
  { label: ['Either', 'edge'], art: 'edges' },
  { label: ['Blazing fast', 'native app'], art: 'swift', circled: true },
];

/** The three steps. */
export const STEPS = [
  {
    n: '01',
    title: 'Install and launch',
    body: 'DevNotch looks for the AI tools you already have and turns on a slot for each one it finds. There is nothing to connect.',
  },
  {
    n: '02',
    title: 'Pick your three',
    body: `The notch holds ${SLOT_COUNT} rings. Choose which of the ${INTEGRATIONS.length} integrations occupy them — the rest stay out of the way.`,
  },
  {
    n: '03',
    title: 'Hover to read it',
    body: 'At rest it is a sliver. Hover and the rings appear; focus one and a card gives you the window, the percentage and the reset time.',
  },
] as const;

/**
 * FAQ. Answers are drawn from the app's own README and source — particularly
 * the Keychain behaviour, which is the question most worth answering honestly.
 */
export const FAQS = [
  {
    q: 'Does it need my API keys?',
    a: 'No. For the plan allowance, DevNotch reads the session the tool on your Mac already holds. An API key is optional on two slots and adds a separate figure — organisation usage for Claude, API spend for Codex — never the plan allowance itself.',
  },
  {
    q: 'Why does macOS ask for Keychain permission?',
    a: 'Reading Claude Code’s stored session means reading a Keychain item that belongs to Claude Code, not to DevNotch, so macOS asks you once. The token is used for exactly one request — Anthropic’s own usage endpoint, for your own account — and is never stored, logged or sent anywhere else. Decline and DevNotch falls back to the cached figure.',
  },
  {
    q: 'Does it refresh the tokens it reads?',
    a: 'Never. Refreshing would rotate the token and sign you out of your own CLI. DevNotch only ever reads; when a token expires, the card tells you to run the tool once.',
  },
  {
    q: 'Why is Codex’s number sometimes old?',
    a: 'OpenAI reports the Codex allowance only in the reply to a model request — there is no endpoint to ask. Codex records each figure locally, so DevNotch reads the newest one. Polling would mean spending the allowance in order to measure it, so the card states the reading’s age instead.',
  },
  {
    q: 'Does it scrape anything?',
    a: 'No browser scraping, no reading cookies, no reading terminal contents. Antigravity is the one CLI-derived slot: DevNotch runs `agy` in an empty directory and reads its own usage panel. That is labelled CLI-derived and ranked below an API reading.',
  },
  {
    q: 'Is there a Windows build?',
    a: 'No. The notch window, the status item and the Keychain access are AppKit, so DevNotch is macOS-only today.',
  },
  {
    q: 'What does it cost?',
    a: 'Nothing. It is MIT-licensed and the whole source is on GitHub.',
  },
] as const;

/**
 * Where the download CTAs point. A real page, not an in-page anchor, so the
 * button navigates the way the reference's does. When a macOS build exists,
 * `DOWNLOADS[0].url` is what that page hands over.
 */
export const DOWNLOAD_PATH = '/download';

/** Navigation. Every href resolves to a real page or an existing section. */
export const NAV_LINKS = [
  { label: 'Features', href: '#features' },
  { label: 'Integrations', href: '#integrations' },
  { label: 'FAQs', href: '#faq' },
  { label: 'Download', href: DOWNLOAD_PATH },
] as const;

export const SEO = {
  title: `${PRODUCT.name} — AI usage, on the edge of your Mac`,
  description:
    'DevNotch is a macOS notch that shows how much of your AI quota you have left. Claude, Codex, OpenCode, Kilo Code, Antigravity, Hermes and OpenRouter — read from the tools already on your Mac.',
} as const;
