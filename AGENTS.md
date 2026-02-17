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
open build/AudioInput.app                # Run app
./scripts/integration-test.sh            # API integration tests
```

## Code Conventions

- Follow existing patterns in the codebase
- Prefer explicit over clever
- Delete dead code immediately

## Architecture

`Sources/AudioInput/` — Models/, Services/, Views/, Utilities/
See `SPEC.md` for full architecture. See `MARKET_RESEARCH.md` for research.
