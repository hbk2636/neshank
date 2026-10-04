# Neshank Documentation

Guides and technical references for **Neshank** — the native, offline-first bookmark
manager for macOS (SwiftUI + SQLite, MIT license).

| Document | What it covers |
|----------|----------------|
| [Mind Map Designer](mindmap/README.md) | End-to-end guide to the link → visual mind map tool: pipeline, quality gate, layouts, themes, exports, storage and testing |
| [Video Downloader](ytdl/README.md) | End-to-end guide to the built-in downloader: source detection, output formats, cookies, bundled engine and testing |
| [Architecture](superpowers/specs/architecture.md) | As-built architecture of v1: layers, data model, AI configuration, security notes and build/test workflow |

Screenshots and the demo GIF live in [`assets/`](assets/).

> Neshank is offline-first: everything in these guides works without an account or a
> cloud service. Network is used only for fetching page metadata, screenshots, link
> checks, downloads and *your own* AI provider.
