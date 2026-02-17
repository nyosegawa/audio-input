# AudioInput - Mac用AI音声入力支援ツール 仕様書

## 概要

**AudioInput**は、macOSメニューバーに常駐し、グローバルホットキーで音声録音を開始し、AIモデルで高精度に文字起こしし、アクティブなアプリケーションにテキストを挿入するネイティブツール。

## 技術スタック

- **言語:** Swift 6
- **UI:** SwiftUI (MenuBarExtra)
- **ビルド:** Swift Package Manager (Xcode IDE不要)
- **音声録音:** AVAudioEngine (16kHz WAV)
- **音声認識:** OpenAI gpt-4o-mini-transcribe (デフォルト) / Gemini 2.0 Flash (選択可)
- **テキスト整形:** OpenAI gpt-4o-mini (6モード)
- **テキスト挿入:** NSPasteboard + CGEvent (Cmd+V) + 2秒後クリップボード復元
- **ホットキー:** Carbon RegisterEventHotKey API
- **最小OS:** macOS 14 (Sonoma)

## アーキテクチャ

```
Sources/AudioInput/
├── App.swift                  # @main, MenuBarExtra, AppDelegate
├── Models/
│   ├── AppState.swift         # 全体状態管理 (idle/recording/transcribing/processing/error)
│   └── Settings.swift         # UserDefaults永続化 + .envファイル読み込み
├── Services/
│   ├── AudioRecorder.swift    # AVAudioEngine録音 + 音声レベル監視
│   ├── HotkeyManager.swift    # グローバルホットキー (Carbon API)
│   ├── TranscriptionService.swift  # Protocol定義
│   ├── OpenAITranscriber.swift     # OpenAI API (multipart upload)
│   ├── GeminiTranscriber.swift     # Gemini API (base64 inline)
│   ├── TextProcessor.swift    # AI整形 (6プリセット)
│   └── TextInserter.swift     # クリップボード+Cmd+V+復元
├── Views/
│   ├── MenuBarView.swift      # メニューバードロップダウン
│   ├── RecordingOverlay.swift # フローティングオーバーレイ + 音声レベルバー
│   ├── SettingsView.swift     # 設定画面
│   └── HistoryView.swift      # 転写履歴 (最新50件)
└── Utilities/
    ├── MultipartFormData.swift # HTTP multipart builder
    └── KeyCodes.swift         # キーコード + modifier定数
```

## 実装済み機能

### Phase 1 (MVP) - Done
1. メニューバー常駐 (マイクアイコン、Dockアイコン非表示)
2. グローバルホットキー (Option+Space デフォルト)
3. プッシュトゥトーク (ホットキー押下中に録音)
4. 録音中の視覚フィードバック (フローティングオーバーレイ + 音声レベルバー)
5. OpenAI gpt-4o-mini-transcribe での文字起こし
6. クリップボード経由テキスト挿入 + 2秒後クリップボード復元
7. 基本設定 (APIキー, ホットキー, 言語)
8. 録音開始/停止のサウンドフィードバック

### Phase 2 - Done
9. トグルモード (1回押し開始、もう1回押し停止)
10. Gemini 2.0 Flash 対応
11. 転写履歴 (最新50件保持、コピー可能)
12. AI整形モード 6種 (そのまま/整形/丁寧語/カジュアル/メール/コード)
13. メニューバーからクイックモード切替
14. ログイン時自動起動設定

### Phase 3 - Future
15. オーディオ入力デバイス選択
16. WhisperKit統合 (ローカルモデル)
17. カスタムプロンプト入力

## API検証結果

| モデル | 5.5秒日本語音声のレイテンシ | 精度 |
|--------|---------------------------|------|
| gpt-4o-mini-transcribe | 0.81s | 完璧 (完全一致) |
| whisper-1 | 0.77s | 高 |
| gemini-2.0-flash | 1.57s | 高 (句読点差のみ) |
| gpt-4o-transcribe | 1.88s | 完璧 |

## ビルド & 実行

```bash
swift build                    # デバッグビルド
./scripts/build-app.sh         # .appバンドル作成
open build/AudioInput.app      # アプリ起動
./scripts/integration-test.sh  # API統合テスト
```
