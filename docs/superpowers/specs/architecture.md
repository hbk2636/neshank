# Neshank — As-Built Architecture (v1.0)

This document describes how Neshank is actually built as shipped in **v1.0** — it
replaces the earlier design proposals in this folder, which described pre-release
plans and are obsolete.

## Layer map

```
Sources/NeshankYar/
├── Models/        # pure data: Bookmark, Tag, Chat, MindMapDocument,
│                  # Localization (en/fa/ru/zh dictionary), SeedContent, Digits
├── Store/         # SQLite layer: Database, Library (the app-wide model),
│                  # SearchIndex (FTS5 + LIKE fallback), BackupService, URLNormalizer
├── Services/      # side-effectful: AIClient (AI chat), MindMapAIService,
│                  # PageContentReader (WKWebView + Readability/Turndown),
│                  # YtDlp, VideoBackends, LinkChecker, ImportExport,
│                  # MindMapExport, Screenshotter, PageMeta, HotKey, HTMLText
└── Views/         # SwiftUI: Sidebar/ListView/DetailView, Design shells
    └── Designs/   #   Classic · Aurora · Focus · Dashboard · Atlas · Orbit
```

Rules of thumb:

- **The Store (SQLite) layer is UI-agnostic**; Models carry data plus SwiftUI value
  types (colors/themes) but no view logic — together they compile into the test harness
  (`Scripts/run_tests.sh` links `Models/ + Store/ + Services/ + UIDesign` only;
  `App/` and `Views/` are excluded because `@main` collides with the harness entry).
- All user-visible strings live in **one localization dictionary** (`Localization.swift`)
  with four languages; CI-style checks fail on empty fields or duplicate keys.
- Network access happens only in `Services/`, always behind an explicit user action.

## Data model

Single local SQLite database in `~/Library/Application Support/NeshankYar/`
(WAL mode):

| Table group | Notes |
|-------------|-------|
| `bookmarks`, `folders`, `tags` (+ join tables) | hierarchical folders, multi-tags, trash with 30-day retention, `normalized_url` for duplicate detection |
| page archive + `…_fts` | full text of saved pages, SQLite **FTS5** with automatic `LIKE` fallback when FTS is unavailable |
| `mind_maps` | mind maps as **independent records** (not blobs on bookmarks): `title`, `source_url`, `normalized_url`, `content_hash`, `mind_map_json`, `raw_markdown`, `model`, `language`, `node_count` |
| `chats` / messages | per-bookmark and library-wide conversations with citations |
| backups | daily automatic snapshots + manual backup/restore (`BackupService`) |

Schema changes are gated by `user_version` and migrated forward in `Self.migrate(db)`
— migrations never drop user data. `node_count` is denormalized onto `mind_maps` at
write time so list rendering never parses JSON.

## AI configuration

`AIConfig` (in `AIClient.swift`) is **bring-your-own**:

- `baseURL`, `model`, `profile` are read from `UserDefaults` (`aiBaseURL`, `aiModel`,
  `aiProfile`); **there is no default cloud endpoint** — `defaultBaseURL` and
  `defaultModel` are empty strings, so a fresh install reports *not configured*
  until the user fills Settings → Assistant.
- The API key lives in this Mac's preferences only (a legacy one-time migration from
  Keychain runs on load, then the Keychain item is deleted so ad-hoc builds never
  pop password prompts).
- Requests are plain OpenAI-compatible `POST …/chat/completions` with
  `Authorization: Bearer`, an app-identifying `User-Agent` and an optional
  `x-opencode-session` header.
- `systemPrompt(...)` assembles a per-bookmark prompt: profile, bookmark metadata,
  saved date, tags, note and (capped) page text; when page text is absent it falls
  back to an explicit placeholder instead of hallucinating context.
- Reasoning models get an optional `reasoning_effort` field (`low`/`null`) plus
  `max_tokens` — only when explicitly configured.

Two prompt surfaces are tuned for **small/free models**:

1. **Chat** — short, structured, honest answers with `[n]` citations for library-wide questions.
2. **Mind map** (`MindMapAIService.prompt`) — output must be *one raw JSON object*
   matching a fixed schema (`meta` + `root` tree), depth ≤ 4, node text ≤ 15 words,
   boilerplate stripped; the response is parsed defensively with fallback paths.

## Mind-map pipeline

```
URL → PageContentReader (WKWebView, isolated, scripts settled)
    → Readability.js  ──fallback──▶ region selector
    → QualityGate (PageContentQuality): ≥250 useful chars | ≥40 words |
                                        ≥1 heading & ≥2 paragraphs
    → Turndown.js → Markdown
    → MindMapAIService (your provider) → JSON tree (validated)
    → canvas.html renderer (JSON-injection only) → 6 layouts × 10 themes
    → Library.createMindMap (independent record: content_hash + node_count)
```

Security properties of the renderer:

- `MindMapWebView` bridge accepts **serialized JSON only** — never source text,
  never executable JavaScript; strings are HTML-escaped before `JSON.parse`.
- `canvas.html` is a single offline file with zero remote references; the same
  guarantee is asserted for exported *Standalone HTML* (data injected via
  `JSON.parse` + auto-call wrapper; the render function template stays untouched).
- The quality gate runs **before** the AI call, so tokens are never spent on menus.

## Video downloader

`VideoSource.detect(url)` routes to one of three backends:

| Backend | Implementation |
|---------|----------------|
| `youtube` | bundled `yt-dlp` process, `--dump-single-json` metadata, progress lines parsed from a persistent buffer (handles partial lines) |
| `aparat` | metadata from Aparat's public `videohash` API; the file itself is fetched with a `URLSession` download task — no `yt-dlp` |
| `direct` | bundled `yt-dlp` handles generic media URLs with the same progress pipeline |

`YtDlp.binaryURL()` resolves the engine as env `NESHANKYAR_YTDLP` → updated copy in
Application Support `tools/` → bundled copy; `ffmpeg` is optional and probed by
actually executing it. All child processes are started with **argument arrays**
(never shell strings) and `PATH` is prefixed with the bundle so the bundled
`deno`/`ffmpeg` are visible to `yt-dlp`.

## Build & test workflow

```bash
./Scripts/build_app.sh          # release: .app + icon + ad-hoc sign + DMG
./Scripts/build_app.sh debug    # fast debug build
zsh Scripts/run_tests.sh        # 57 checks — exit 1 on failure (CI-friendly)
```

- **No Xcode required** — only Command Line Tools; `swiftc -swift-version 5` builds
  both the app and the test harness.
- A release build downloads **pinned, hash-verified** tools once: `yt-dlp`
  (SHA-256), arm64 `ffmpeg-static`, `deno` + `bgutil-ytdlp-pot-provider`.
- The harness compiles `Models + Store + Services + Designs/UIDesign` together with
  `Tests/NeshankTest/main.swift`; `App/` and `Views/` are excluded (`@main` clash).
- CI (GitHub Actions) runs `swift build` + the harness on every push; tests return
  exit code 1 on failure.
- Additional standalone harnesses live in `Tests/`: `main.swift` (functional suite,
  includes network checks), `live_mindmap.swift` (end-to-end pipeline run) and
  `mindmap_store.swift` (map storage round-trip) — compile them the same way as the
  main suite (see the header of each file).

## Related documents

- [Mind Map Designer guide](../../mindmap/README.md)
- [Video Downloader guide](../../ytdl/README.md)
- [Repository README](../../README.md)
