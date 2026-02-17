# AudioInput - Mac用AI音声入力支援ツール 仕様書

## 概要

**AudioInput**は、macOSメニューバーに常駐し、グローバルホットキーで音声録音を開始し、AIモデルで高精度に文字起こしし、アクティブなアプリケーションにテキストを挿入するネイティブツール。

## 技術スタック

- **言語:** Swift 6
- **UI:** SwiftUI (MenuBarExtra)
- **ビルド:** Swift Package Manager (Xcode IDE不要)
- **音声録音:** AVAudioEngine
- **音声認識:** OpenAI gpt-4o-mini-transcribe (デフォルト) / Gemini 2.0 Flash (選択可)
- **テキスト挿入:** NSPasteboard + CGEvent (Cmd+V) + クリップボード復元
- **ホットキー:** Carbon RegisterEventHotKey API
- **最小OS:** macOS 14 (Sonoma)

## アーキテクチャ

```
Sources/AudioInput/
├── App.swift                  # @main, MenuBarExtra
├── Models/
│   ├── AppState.swift         # ObservableObject, 全体状態管理
│   └── Settings.swift         # UserDefaults永続化
├── Services/
│   ├── AudioRecorder.swift    # AVAudioEngine録音
│   ├── HotkeyManager.swift    # グローバルホットキー登録
│   ├── TranscriptionService.swift  # Protocol
│   ├── OpenAITranscriber.swift     # OpenAI API実装
│   ├── GeminiTranscriber.swift     # Gemini API実装
│   ├── TextInserter.swift     # クリップボード+Cmd+V+復元
│   └── AudioLevelMonitor.swift # 音声レベル監視
├── Views/
│   ├── MenuBarView.swift      # メニューバードロップダウン
│   ├── RecordingOverlay.swift # 録音中オーバーレイ
│   ├── SettingsView.swift     # 設定画面
│   └── HistoryView.swift      # 履歴表示
└── Utilities/
    ├── MultipartFormData.swift # HTTP multipart
    └── KeyCodes.swift         # キーコード定数
```

## 機能仕様

### Phase 1 (MVP)
1. メニューバー常駐 (マイクアイコン、Dockアイコン非表示)
2. グローバルホットキー (Option+Space デフォルト)
3. プッシュトゥトーク (ホットキー押下中に録音)
4. 録音中の視覚フィードバック (フローティングオーバーレイ + 音声レベル表示)
5. OpenAI gpt-4o-mini-transcribe での文字起こし
6. クリップボード経由テキスト挿入 + 2秒後クリップボード復元
7. 基本設定 (APIキー, ホットキー, 言語)

### Phase 2
8. トグルモード (1回押し開始、もう1回押し停止)
9. Gemini 2.0 Flash 対応
10. 転写履歴 (最新50件保持、コピー可能)
11. AI整形モード (LLMによるテキスト後処理)

### Phase 3
12. 複数AIプロンプトプリセット (チャット/メール/コード)
13. ログイン時自動起動
14. オーディオ入力デバイス選択

## API検証結果

| モデル | 5.5秒日本語音声のレイテンシ | 精度 |
|--------|---------------------------|------|
| gpt-4o-mini-transcribe | 0.81s | 完璧 |
| whisper-1 | 0.77s | 高 |
| gemini-2.0-flash | 1.57s | 高 |
| gpt-4o-transcribe | 1.88s | 完璧 |
