# Agent Guidelines

## Core Principles

- **Do NOT maintain backward compatibility** unless explicitly requested.
- **Keep this file under 20-30 lines.**

## Project Overview

**Project type:** macOS native menu bar app (AI voice input tool)
**Primary language:** Swift 6 + SwiftUI
**Key dependencies:** AVAudioEngine, Carbon (hotkeys), OpenAI API, Gemini API

## Commands

```bash
swift build                              # Build
swift build -c release                   # Release build
./scripts/build-app.sh                   # Create .app bundle
./scripts/build-dmg.sh                   # Create DMG installer
open build/AudioInput.app                # Run app
./scripts/integration-test.sh            # API integration tests
```

## Release Flow

```bash
git tag v1.2.3 && git push origin v1.2.3
```

これだけで以下が全自動実行される（`.github/workflows/release.yml`）:
1. whisper.cpp ビルド → `swift build -c release` → .app バンドル作成
2. DMG パッケージング → GitHub Releases に公開
3. `nyosegawa/homebrew-tap` の Cask バージョン + SHA256 を自動更新

**前提:** `HOMEBREW_TAP_TOKEN` シークレットが設定済みであること。
**署名:** 未署名（ad-hoc）。Homebrew Cask の `postflight` で `xattr -cr` を実行。
**注意:** 開発版（`build/AudioInput.app`）とリリース版（`/Applications/AudioInput.app`）を同時に使うと TCC 権限が競合するため、テスト時はどちらか一方のみ使用する。

## Code Conventions

- Follow existing patterns in the codebase
- Prefer explicit over clever
- Delete dead code immediately

## Architecture

`Sources/AudioInput/` — Models/, Services/, Views/, Utilities/
See `SPEC.md` for full architecture. See `MARKET_RESEARCH.md` for research.
