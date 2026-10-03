# Contributing to Neshank

Thanks for helping — Neshank is a small, fast-moving macOS app and good contributions are welcome.

## Ground rules
- **Scope:** Neshank is an *offline-first bookmark manager for macOS* (SwiftUI + SQLite). Features that require an account, a cloud backend, or telemetry are out of scope by design.
- **Targets:** macOS 13+, Apple Silicon, Swift 5.9+, no Xcode required (Command Line Tools only).

## Dev setup
```bash
git clone https://github.com/hbk2636/neshank.git
cd neshank
zsh Scripts/run_tests.sh       # 57 checks — must pass
./Scripts/build_app.sh debug   # quick debug build -> build/نشانک.app
open "build/نشانک.app"
```

## Before you open a PR
1. `zsh Scripts/run_tests.sh` exits 0 (CI runs the same script on every push).
2. New user-facing strings go into the localization dictionary (`fa` / `en` / `ru` / `zh`) — the suite checks dictionary health.
3. Update the README if you change shortcuts, install steps, or architecture.
4. One logical change per PR; describe *why*, not just *what*.

## Style
- Swift: keep views small; logic lives in `Store/` and `Services/`; **no new third-party dependencies**.
- Commit messages: imperative and scoped (`Fix:`, `Feat:`, `Docs:`).

## Reporting bugs
Use the **Bug report** issue template: macOS version, app version, steps to reproduce, expected vs actual, and any console output.
