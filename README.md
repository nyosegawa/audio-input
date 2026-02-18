# AudioInput

macOSメニューバーに常駐するAI音声入力ツール。グローバルホットキーで録音を開始し、音声認識結果をアクティブなアプリケーションのカーソル位置に自動挿入する。

## 特徴

- **ローカル音声認識** — whisper.cpp (GGML + Metal) によるオフライン・リアルタイム文字起こし
- **日本語特化モデル** — kotoba-whisper v2.0 対応
- **クラウド音声認識** — OpenAI gpt-4o-mini-transcribe / Gemini 2.5 Flash も選択可能
- **リアルタイムストリーミング** — 録音中に仮説テキストをオーバーレイ表示
- **テキスト整形** — OpenRouter経由で任意のLLMによるテキスト整形（フィラー除去、丁寧語変換、メール文、コードコメントなど）
- **グローバルホットキー** — Option+Space (デフォルト) でどのアプリからでも起動
- **Push to Talk / Toggle** — 押している間だけ録音、または1回押しで開始/停止
- **無音検出** — Toggle モードで無音が続くと自動停止
- **転写履歴** — 最新50件を保持、検索・エクスポート可能

## 動作要件

- macOS 14 (Sonoma) 以降
- Apple Silicon (M1/M2/M3/M4)
- Swift 6 (Command Line Tools)
- マイクおよびアクセシビリティの権限許可

## ビルド・実行

```bash
# whisper.cppライブラリのビルド + アプリバンドル作成
./scripts/build-app.sh

# アプリ起動
open build/AudioInput.app
```

開発時:

```bash
swift build           # デバッグビルド
swift build -c release  # リリースビルド
```

## 設定

### APIキー (.env)

プロジェクトルートに `.env` ファイルを作成:

```
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
OPENROUTER_API_KEY=sk-or-...
```

アプリ内の設定画面からも入力可能。

### 音声認識プロバイダ

| プロバイダ | 特徴 |
|-----------|------|
| ローカル (whisper.cpp) | オフライン、無料、リアルタイム表示。デフォルト |
| OpenAI | 高精度、低レイテンシ ($0.003/分) |
| Gemini | 無料枠あり |

### ローカルモデル

| モデル | サイズ | 備考 |
|--------|--------|------|
| Tiny Q5 | ~32MB | 高速・低精度 |
| Base | ~148MB | バランス |
| Small Q5 | ~190MB | 高精度 |
| Large v3 Turbo Q5 | ~574MB | 最高精度 |
| Kotoba v2.0 Q5 | ~538MB | 日本語特化 |

設定画面から選択・ダウンロード・切り替えが可能。

## アーキテクチャ

```
Sources/AudioInput/
├── App.swift                     # @main, MenuBarExtra, AppDelegate
├── Models/
│   ├── AppState.swift            # アプリ状態管理 (@Observable)
│   └── Settings.swift            # UserDefaults + .env読み込み
├── Services/
│   ├── AudioRecorder.swift       # AVAudioEngine録音
│   ├── WhisperTranscriber.swift  # whisper.cpp統合 (ストリーミング対応)
│   ├── OpenAITranscriber.swift   # OpenAI API
│   ├── GeminiTranscriber.swift   # Gemini API
│   ├── OpenRouterService.swift   # OpenRouterモデル一覧取得
│   ├── TextProcessor.swift       # OpenRouter経由テキスト整形
│   ├── TextInserter.swift        # AX API / クリップボード+Cmd+V
│   └── HotkeyManager.swift      # Carbon グローバルホットキー
├── Views/
│   ├── MenuBarView.swift         # メニューバードロップダウン
│   ├── RecordingOverlay.swift    # フローティングオーバーレイ
│   ├── SettingsView.swift        # 設定画面
│   └── HistoryView.swift         # 転写履歴
└── Utilities/
    ├── Logger.swift              # ファイルログ (/tmp/audioinput.log)
    ├── KeyCodes.swift            # キーコード定数
    ├── RetryHelper.swift         # 指数バックオフリトライ
    └── MultipartFormData.swift   # HTTP multipart builder
```

## ライセンス

MIT
