# Agent Guidelines

## Core Principles

- **Do NOT maintain backward compatibility** unless explicitly requested.
- **Keep this file under 20-30 lines.**

## Project Overview

**Project type:** macOS native menu bar app (AI voice input tool)
**Primary language:** Swift 6 + SwiftUI
**Key dependencies:** AVAudioEngine, Carbon (hotkeys), whisper.cpp, OpenAI/Gemini API

## Commands

```bash
swift build                              # Build
./scripts/build-app.sh                   # Create .app bundle
./scripts/build-dmg.sh                   # Create DMG installer
./scripts/integration-test.sh            # API integration tests
```

## Release: `git tag vX.Y.Z && git push origin vX.Y.Z`

CI自動実行: ビルド → DMG → GitHub Releases → homebrew-tap更新。前提: `HOMEBREW_TAP_TOKEN` secret。未署名(ad-hoc)、Cask postflightで`xattr -cr`。開発版とリリース版の同時使用はTCC権限競合するため禁止。

## Code Conventions

- Follow existing patterns. Prefer explicit over clever. Delete dead code immediately.
- `Sources/AudioInput/` — Models/, Services/, Views/, Utilities/. See `SPEC.md`.
