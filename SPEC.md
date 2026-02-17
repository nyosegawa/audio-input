# AudioInput - Mac用AI音声入力支援ツール 仕様書

## 概要

**AudioInput**は、macOSメニューバーに常駐し、グローバルホットキーで音声録音を開始し、AIモデルで高精度に文字起こしし、アクティブなアプリケーションにテキストを挿入するネイティブツール。

## 技術スタック

- **言語:** Swift 6
- **UI:** SwiftUI (MenuBarExtra)
- **ビルド:** Swift Package Manager (Xcode IDE不要)
- **音声録音:** AVAudioEngine (16kHz WAV)
- **音声認識:** WhisperKit ローカルモデル (デフォルト) / OpenAI gpt-4o-mini-transcribe / Gemini 2.5 Flash
- **ローカルモデル:** WhisperKit 0.15.0 (Apple Silicon最適化、リアルタイムストリーミング)
- **デバイス選択:** CoreAudio API (AudioObjectGetPropertyData / AudioUnitSetProperty)
- **テキスト整形:** OpenAI gpt-4o-mini (6プリセット + カスタムプロンプト)
- **テキスト挿入:** NSPasteboard + CGEvent (Cmd+V) + changeCount検知スマート復元
- **ホットキー:** Carbon RegisterEventHotKey API
- **最小OS:** macOS 14 (Sonoma)

## アーキテクチャ

```
Sources/AudioInput/
├── App.swift                  # @main, MenuBarExtra, AppDelegate
├── Models/
│   ├── AppState.swift         # 全体状態管理 + 履歴永続化 (JSON)
│   └── Settings.swift         # UserDefaults永続化 + .envファイル読み込み
├── Services/
│   ├── AudioRecorder.swift    # AVAudioEngine録音 + 音声レベル監視 + フロートサンプル蓄積
│   ├── HotkeyManager.swift    # グローバルホットキー (Carbon API)
│   ├── PermissionChecker.swift # マイク・アクセシビリティ権限チェック
│   ├── TranscriptionService.swift  # Protocol定義
│   ├── WhisperKitTranscriber.swift # WhisperKitローカルモデル (ストリーミング対応)
│   ├── OpenAITranscriber.swift     # OpenAI API (multipart upload)
│   ├── GeminiTranscriber.swift     # Gemini API (base64 inline)
│   ├── TextProcessor.swift    # AI整形 (6プリセット + カスタム)
│   └── TextInserter.swift     # クリップボード+Cmd+V+復元
├── Views/
│   ├── MenuBarView.swift      # メニューバードロップダウン + 権限警告
│   ├── RecordingOverlay.swift # フローティングオーバーレイ + 音声レベルバー
│   ├── SettingsView.swift     # 設定画面
│   └── HistoryView.swift      # 転写履歴 (最新50件)
└── Utilities/
    ├── MultipartFormData.swift # HTTP multipart builder
    ├── RetryHelper.swift      # 指数バックオフリトライ
    └── KeyCodes.swift         # キーコード + modifier定数
```

## 実装済み機能

### Phase 1 (MVP) - Done
1. メニューバー常駐 (マイクアイコン、Dockアイコン非表示)
2. グローバルホットキー (Option+Space デフォルト)
3. プッシュトゥトーク (ホットキー押下中に録音)
4. 録音中の視覚フィードバック (フローティングオーバーレイ + 音声レベルバー)
5. OpenAI gpt-4o-mini-transcribe での文字起こし
6. クリップボード経由テキスト挿入 + スマートクリップボード復元 (changeCount検知)
7. 基本設定 (APIキー, ホットキー, 言語)
8. 録音開始/停止のサウンドフィードバック

### Phase 2 - Done
9. トグルモード (1回押し開始、もう1回押し停止)
10. Gemini 2.5 Flash 対応
11. 転写履歴 (最新50件保持、コピー可能)
12. AI整形モード 6種 (そのまま/整形/丁寧語/カジュアル/メール/コード)
13. メニューバーからクイックモード切替
14. ログイン時自動起動設定

### Phase 3 - Done
15. オーディオ入力デバイス選択 (CoreAudio API)
16. カスタムテキスト処理プロンプト (ユーザー定義のシステムプロンプト)
17. 短い録音のフィードバック表示 (0.3秒未満の録音時にオーバーレイ通知)
18. スマートクリップボード復元 (changeCount検知で外部コピーを保護)

### Phase 4 - Done
19. 成功フィードバック (転写テキストを2秒間オーバーレイ表示)
20. 録音経過時間表示 (オーバーレイにタイマー表示、TimelineView)
21. 無音検出による自動停止 (トグルモード時、設定可能な無音時間で自動停止)

### Phase 5 - Done
22. 転写履歴の永続化 (Application Support/AudioInput/history.json)
23. マイク・アクセシビリティ権限チェック (起動時 + 録音開始時)
24. APIリトライ (指数バックオフ、ネットワークエラー/429/5xx対応、最大3回)
25. 転写キャンセル (転写中/処理中にホットキーでキャンセル)

### Phase 5.5 (UX改善) - Done
26. マルチモニター対応 (マウスのある画面にオーバーレイ表示)
27. 履歴検索 (テキストフィルタリング)
28. 履歴エクスポート (テキストファイル出力)
29. キャンセル時の一時ファイルクリーンアップ
30. ネットワークエラーメッセージ詳細化 (タイムアウト/DNS/接続不可の区別)
31. テキスト整形失敗時のフォールバック通知
32. AVAudioEngine起動失敗時のリソースクリーンアップ
33. 権限警告からシステム設定を直接開くリンク
34. 入力デバイス切断時のシステムデフォルトフォールバック
35. 設定画面の全項目にヘルプテキスト追加

### Phase 6 (ローカルモデル + リアルタイム表示) - Done
36. WhisperKit統合 (ローカルオンデバイス音声認識、Apple Silicon最適化)
37. リアルタイムストリーミング表示 (録音中に仮説テキストをオーバーレイ表示)
38. 4モデルサイズ選択 (Tiny/Base/Small/Large-v3-Turbo)
39. 自動モデルダウンロード + 進捗表示 (初回使用時)
40. ローカルモデルをデフォルトプロバイダに設定 (オフライン・無料・低レイテンシ)
41. 録音中の16kHzフロートサンプル蓄積 (AudioRecorder拡張)
42. 1.5秒間隔のストリーミング転写ループ (WhisperKitTranscriber)

## API検証結果

| モデル | 5.5秒日本語音声のレイテンシ | 精度 |
|--------|---------------------------|------|
| gpt-4o-mini-transcribe | 0.81s | 完璧 (完全一致) |
| whisper-1 | 0.77s | 高 |
| gemini-2.5-flash | 1.40s | 高 (句読点差のみ) |
| gpt-4o-transcribe | 1.88s | 完璧 |

## ビルド & 実行

```bash
swift build                    # デバッグビルド
./scripts/build-app.sh         # .appバンドル作成
open build/AudioInput.app      # アプリ起動
./scripts/integration-test.sh  # API統合テスト
```
