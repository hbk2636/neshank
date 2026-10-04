# Video Downloader

A complete, free video downloader built into Neshank — **no account, no server, no
paid API, zero setup**. This guide describes the feature as shipped in **v1.0**.

<p align="center">
  <img src="../assets/screenshot-downloader.png" width="820" alt="Built-in video downloader — YouTube, Aparat and generic sites, live progress">
</p>

## Opening the tool

| Route | How |
|-------|-----|
| Sidebar | **Tools → Video Downloader** |
| Command palette | Press **⌘K**, type *video* |
| Tools menu | **⋯ → Tools → Video Downloader** in every UI shell |
| Selected bookmark | A selected YouTube/Aparat bookmark pre-fills the URL field |

It opens in its own window (default 900×640, minimum 720×520).

## Supported sources

| Source | Engine | Notes |
|--------|--------|-------|
| **YouTube** (`youtube.com`, `youtu.be`) | bundled `yt-dlp` | may require browser cookies — see [YouTube access](#youtube-access) |
| **Aparat** (`aparat.com/v/HASH`) | direct public API + `URLSession` | no `yt-dlp` call: metadata (title, poster, duration) comes from Aparat's endpoint and the file is fetched with byte-level progress |
| **Direct media links** (`.mp4`, `.m3u8`, …) | bundled `yt-dlp` | generic yt-dlp handling, same progress line as YouTube |
| **1,700+ other sites** (SoundCloud, TikTok, Dailymotion, …) | bundled `yt-dlp` | whatever `yt-dlp` supports |

The source is detected automatically from the pasted URL — no mode switch needed.

## Output formats

| Mode | What you get | Requires ffmpeg |
|------|--------------|-----------------|
| **Audio (M4A)** | best audio stream, no video | no (single-stream fallback works without it) |
| **Video (720p)** | best video ≤ 720p merged with audio | yes (bundled) |

**v1 caps video at 720p**; higher quality is on the roadmap. Aparat always delivers
its best available file regardless of the output picker (the picker only
matters for the yt-dlp/YouTube path).

## Downloading

1. Paste a URL — after a short debounce the **metadata card** fills in: title, channel,
   duration and thumbnail (from `yt-dlp --dump-single-json` or the Aparat API).
2. Pick **Audio (M4A)** or **Video (720p)**.
3. Optionally change the destination — **Destination Folder → Change…**.
   Default: a dedicated subfolder of `~/Downloads`, created automatically on first use.
4. Press **Download** — a live progress line shows percent, speed and ETA, and the
   step checklist walks **Link → Details → Download → Done** (confetti included).
5. **Show in Finder** when finished; **New Download** for the next one; the session's
   files stay in **Recent Downloads**.

Cancel is available at any time; a failed run offers **Try Again** with the same URL.

## YouTube access

YouTube frequently requires authenticated cookies for downloads. In the tool's
**YouTube Access** section choose one of:

- **Use installed browser** — cookies are read from the selected browser and stay
  **on this Mac**; they are never uploaded anywhere.
- **Import cookies.txt File** — export cookies with a browser extension
  (e.g. *Get cookies.txt LOCALLY*) and import the file; **Remove** deletes the copy.

The active state is shown as *Cookies file is active*.

## Bundled engine

Nothing to install: a release build embeds the tools inside the app and the app runs
them with an argument-array process (URLs are never interpolated through a shell):

- **`yt-dlp`** — pinned version (`2026.08.19`), SHA-256 verified at build time,
  ad-hoc signed.
- **`ffmpeg`** (arm64 static build) — merges video+audio for the 720p mode; detected
  by actually executing it (Rosetta not assumed).
- **`deno` + `bgutil-ytdlp-pot-provider`** — PO-token tooling for YouTube challenges.

Binary resolution order at runtime:

1. `NESHANKYAR_YTDLP` environment variable (development/testing override)
2. updated copy in `~/Library/Application Support/NeshankYar/tools/yt-dlp`
3. the copy bundled next to the app executable

If none is found the tool reports *"The yt-dlp tool was not found inside the app."* —
reinstalling the DMG restores it.

## Testing

```bash
zsh Scripts/run_tests.sh
```

`Tests/NeshankTest/main.swift` covers, among others:

- progress-line parsing (percent, total size, speed, ETA) and ignoring non-progress lines
- audio/video argument building — no `--merge-output-format` for audio, `height<=720`
  cap for video, URL always last, output template present
- metadata JSON decoding and duration/file-size formatting
- source detection (YouTube / Aparat / direct) and Aparat ID extraction
- `yt-dlp` binary resolution (env override, missing binary → `nil`)

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| *The yt-dlp tool was not found inside the app* | Reinstall the DMG, or drop an updated `yt-dlp` into `~/Library/Application Support/NeshankYar/tools/` |
| YouTube download fails / bot check | YouTube Access → use browser cookies (see above) |
| Video has no sound | ffmpeg missing/not running — audio-only mode still works; reinstall restores ffmpeg |
| Nothing happens on Download | Check the destination folder is writable; try **Try Again** |

As with any downloader: respect each site's terms of service.
