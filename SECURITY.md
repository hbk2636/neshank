# Security Policy

## Supported versions
The latest release (v1.x) is the only version that receives security fixes.

## Reporting a vulnerability
- **Do not** open a public issue for security reports.
- Contact the maintainer privately with: description, impact, reproduction steps, affected version.
- Expect an acknowledgement within 7 days; confirmed issues ship in the next release.

## Security design notes
- Neshank is offline-first: no telemetry, no accounts, no cloud sync.
- Your AI API key is stored only in local app preferences and sent only to the endpoint *you* configure.
- Archived page text, screenshots and the database live in `~/Library/Application Support/NeshankYar/` on your Mac only.
- Bundled third-party tools (`yt-dlp`, `ffmpeg`, `deno`) are pinned and updated deliberately — report issues in them upstream as well as here.
