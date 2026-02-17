# Agent Guidelines

## Core Principles

- **Do NOT maintain backward compatibility** unless explicitly requested. Break things boldly.
- **Keep this file under 20-30 lines of instructions.**

## Project Overview

**Project type:** macOS native menu bar app (AI voice input tool)
**Primary language:** Swift 6 + SwiftUI
**Key dependencies:** AVAudioEngine, Carbon (hotkeys), OpenAI API, Gemini API

## Commands

```bash
# Build
cd /Users/sakasegawa/src/github.com/nyosegawa/audio-input && swift build

# Test
cd /Users/sakasegawa/src/github.com/nyosegawa/audio-input && swift test

# Run
cd /Users/sakasegawa/src/github.com/nyosegawa/audio-input && swift run AudioInput
```

## Code Conventions

- Follow existing patterns in the codebase
- Prefer explicit over clever
- Delete dead code immediately

## Architecture

See `SPEC.md` for detailed architecture. Key: `Sources/AudioInput/` with Services/, Views/, Models/ structure.
