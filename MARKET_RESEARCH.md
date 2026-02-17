# Mac用AI音声入力支援ツール 市場調査レポート

調査日: 2026-02-17

---

## 目次

1. [既存ツールの市場調査](#1-既存ツールの市場調査)
2. [UI/UX調査](#2-類似アプリケーションのuiux調査)
3. [音声認識モデル比較](#3-音声認識モデル比較)
4. [技術スタック調査](#4-技術スタック調査)
5. [総合所見](#5-総合所見)

---

## 1. 既存ツールの市場調査

### 1.1 macOS標準音声入力機能

| 項目 | 内容 |
|------|------|
| **価格** | 無料（macOS標準搭載） |
| **主な機能** | システム全体でのディクテーション、オフライン処理（Apple Silicon）、66言語対応 |
| **UI/UX** | Fn×2でトリガー、マイクアイコンのフィードバック、システム全体で動作 |
| **使用モデル** | Apple独自のオンデバイスモデル（macOS Tahoe以降はSpeechAnalyzer） |
| **対応言語** | 66言語（日本語含む） |
| **長所** | 無料、OS統合、Apple Siliconでオフライン動作、セットアップ不要 |
| **短所** | セッション60秒制限（改善中）、カスタム辞書なし、高度な機能はネット接続必要、AI整形機能なし |

**2025年の進化:** macOS TahoeではAppleの新しいSpeechAnalyzer APIが導入され、OpenAI Whisperモデルより55%高速に処理可能。34分の動画を45秒で処理できるベンチマーク結果あり。

---

### 1.2 SuperWhisper

| 項目 | 内容 |
|------|------|
| **価格** | 無料プラン / Pro: $8.49/月 or $84.99/年 / Lifetime: $249.99 |
| **主な機能** | ローカルAI音声認識、AI整形、100+言語、プリセット、録音履歴検索、BYO APIキー |
| **UI/UX** | グローバルショートカット、macOS 13+アクセシビリティAPI統合、3種のコンテキスト取得 |
| **使用モデル** | OpenAI Whisper（ローカル実行）、クラウドAIオプション |
| **対応言語** | 100+言語・方言 |
| **長所** | ローカル処理でプライバシー保護、深いmacOS統合、選択テキスト・クリップボード・アプリコンテキスト取得、オフライン動作 |
| **短所** | macOS/iOS限定、Lifetime価格が高い、学習コストあり |

**特筆すべき機能:**
- 選択テキスト（ディクテーション開始時取得）、クリップボードコンテキスト（ディクテーション中取得）、アプリケーションコンテキスト（転写後取得）の3段階コンテキスト
- アクセシビリティAPIでアクティブ入力フィールドの全テキスト取得（スクロール範囲外含む）
- クリップボード復元機能（結果貼り付け3秒後に元のクリップボード値を復元）
- キーストロークシミュレーション出力（実験的、US QWERTYのみ）

---

### 1.3 Wispr Flow

| 項目 | 内容 |
|------|------|
| **価格** | 無料: 2,000語/週 / Pro: $15/月 or $144/年 |
| **主な機能** | クラウドAI音声認識、自動編集、フィラーワード除去、文脈対応トーン調整、ウィスパーモード |
| **UI/UX** | ユニバーサルアプリ対応、自動句読点、大文字処理 |
| **使用モデル** | クラウドベース（独自モデル） |
| **対応言語** | 100+言語（リアルタイム切替可能） |
| **長所** | 97.2%の転写精度、170-179 WPMの入力速度、SOC 2 Type II準拠、クロスプラットフォーム（Mac/Win/iOS） |
| **短所** | **常時ネット接続必須**、クラウド処理（プライバシー懸念）、800MB RAM使用（アイドル時）、起動8-10秒、月額課金 |

**プライバシー懸念:** アクティブウィンドウのスクリーンショットを数秒ごとに撮影しクラウドサーバーに送信。ローカル処理オプションなし。

---

### 1.4 MacWhisper（Whisper Transcription）

| 項目 | 内容 |
|------|------|
| **価格** | 無料（Base/Small） / $8.99/月 / $29.99/年 / Lifetime: $79.99 |
| **主な機能** | ファイル転写、バッチ処理、字幕エクスポート（SRT/VTT）、システムオーディオキャプチャ |
| **UI/UX** | ドラッグ&ドロップ、ファイルベースの転写ワークフロー |
| **使用モデル** | OpenAI Whisper + Nvidia Parakeet（ローカル実行） |
| **対応言語** | 100+言語 |
| **長所** | 完全ローカル処理、Metal/GPU高速化、バッチ処理、iOS/iPad対応 |
| **短所** | リアルタイムディクテーション向きではない（ファイル転写メイン）、UIがシンプル |

---

### 1.5 Talon Voice

| 項目 | 内容 |
|------|------|
| **価格** | 無料（Patreon支援推奨） |
| **主な機能** | 音声コーディング、マウス制御、カスタムスクリプト、ノイズ認識 |
| **UI/UX** | Python 3スクリプトベース、高度にカスタマイズ可能 |
| **使用モデル** | 内蔵音声認識エンジン + Dragon対応 |
| **対応言語** | 英語中心（拡張可能） |
| **長所** | プログラマー向け最強ツール、アイトラッキング対応、完全ハンズフリー操作、無料 |
| **短所** | **設定が非常に複雑**、学習コスト極めて高い、一般ユーザー向きではない、日本語サポート限定的 |

---

### 1.6 VoiceInk

| 項目 | 内容 |
|------|------|
| **価格** | $39 買い切り（2台まで） |
| **主な機能** | ローカルAI音声認識、システム全体ディクテーション、AIテキスト整形、チャットモード/メールモード |
| **UI/UX** | ホットキートリガー、メニューバー常駐 |
| **使用モデル** | Whisperベース（ローカル実行） |
| **対応言語** | 100+言語 |
| **長所** | **オープンソース**、買い切り、99%精度、完全オフライン、Apple Silicon最適化、4.9/5評価 |
| **短所** | Apple Silicon必須（Intel非対応）、macOS限定 |

**注目ポイント:** オープンソースであり、コード監査・カスタマイズ・ベンダーロックインなし。GitHub公開。

---

### 1.7 その他の主要ツール

| ツール名 | 価格 | 特徴 | 処理 |
|----------|------|------|------|
| **Spokenly** | 無料 / Pro $7.99/月 | Whisperベース、プライバシー重視、サインアップ不要 | ローカル |
| **Sotto** | 買い切り | ホットキー→即座にテキスト挿入、ミニマル設計 | ローカル |
| **Willow Voice** | - | 自動フォーマット、フィラーワード除去、静音モード | ローカル |
| **VocaType** | - | 4種のUI（Notch/Mini/Glass/Ghost）、プッシュトゥトーク | ローカル |
| **Voibe** | - | プライバシー重視 | ローカル |

---

### 1.8 市場マップ（ポジショニング）

```
                    クラウド処理
                        |
                   Wispr Flow
                        |
    シンプル ----+---+---+---+---- 高機能
                |   |       |
           Sotto|   |  MacWhisper
          Spokenly  |       |
           VocaType |  SuperWhisper
                    |       |
               VoiceInk     |
                        Talon Voice
                        |
                    ローカル処理
```

---

## 2. 類似アプリケーションのUI/UX調査

### 2.1 ホットキー設計

| アプリ | デフォルトホットキー | 方式 |
|--------|---------------------|------|
| macOS標準 | Fn × 2 | トグル |
| SuperWhisper | カスタマイズ可能グローバルショートカット | プッシュトゥトーク / トグル |
| Wispr Flow | カスタマイズ可能 | プッシュトゥトーク |
| VoiceInk | カスタマイズ可能ホットキー | プッシュトゥトーク |
| VocaType | カスタマイズ可能 | プッシュトゥトーク（デフォルト） |
| Talon Voice | 音声コマンド | 常時リスニング |

**設計パターン:**
- **プッシュトゥトーク（PTT）:** 押している間録音。短い発話に最適。VocaTypeやVoiceInkのデフォルト
- **トグル:** 1回押して開始、もう1回押して停止。長い発話に最適
- **常時リスニング:** Talon Voiceのように常に音声を監視。ウェイクワード方式

**ベストプラクティス:**
- 両方式をサポートし、ユーザーが選択可能にする
- ホットキーのカスタマイズは必須機能
- 他のアプリと競合しないデフォルトキーの選定が重要

### 2.2 メニューバーアプリデザイン

**共通パターン:**
- メニューバーにマイクアイコンまたはアプリアイコンを配置
- クリックでドロップダウンメニュー表示（モード切替、設定、履歴）
- SwiftUIの `MenuBarExtra` で実装可能

**SuperWhisperのアプローチ:**
- メニューバーからモード切替（キーボードから直接も可能）
- 録音履歴の検索機能

### 2.3 音声入力中のビジュアルフィードバック

| アプリ | フィードバック方式 |
|--------|-------------------|
| macOS標準 | 画面下部にマイクアイコン + 波形 |
| VocaType | **4種のスタイル:** Notch（Dynamic Island風）、Mini（ドラッガブル浮遊ウィンドウ）、Glass（半透明オーバーレイ）、Ghost（最小インジケータ） |
| SuperWhisper | 録音インジケータ |
| Wispr Flow | アプリ内インジケータ |

**設計原則:**
- 録音中であることの明確な視覚的確認が必須
- 音声レベルのリアルタイム表示（波形/バー）が望ましい
- 邪魔にならないがはっきり見えるバランスが重要
- 複数のフィードバックスタイルを提供するのがトレンド（VocaType方式）

### 2.4 テキスト挿入方法

| 方式 | 使用アプリ | 長所 | 短所 |
|------|-----------|------|------|
| **クリップボード経由（Cmd+V）** | SuperWhisper, Wispr Flow, VoiceInk | 信頼性が高い、全アプリ対応 | クリップボード上書き |
| **アクセシビリティAPI直接入力** | SuperWhisper（コンテキスト取得用） | ネイティブ入力体験 | アクセシビリティ権限必要、アプリ互換性問題 |
| **キーストロークシミュレーション** | SuperWhisper（実験的） | クリップボード維持 | US QWERTYのみ、日本語非対応の可能性 |

**SuperWhisperの工夫:**
- クリップボード経由で貼り付け後、3秒で元のクリップボード内容を復元する機能
- これにより「クリップボード上書き」問題を軽減

**推奨アプローチ:**
- メイン方式としてクリップボード経由 + クリップボード復元
- 将来的にアクセシビリティAPI直接入力をオプション提供

### 2.5 設定画面デザイン

**一般的な設定項目:**
- ホットキー設定
- モデル選択（大/中/小）
- 言語選択
- AIプロンプト/モード設定（チャット、メール、コード等）
- プライバシー設定
- 起動時に開く設定
- オーディオ入力デバイス選択

### 2.6 オンボーディング体験

**必要なOS権限:**
1. マイクアクセス許可
2. アクセシビリティ許可（テキスト挿入用）
3. 入力モニタリング許可（Wispr Flow）

**ベストプラクティス:**
- 権限付与を段階的にガイド
- 最初の音声入力までの時間を最小化
- モデルダウンロード進捗の表示（ローカルモデル使用時）
- サンプル発話でのテスト機能

---

## 3. 音声認識モデル比較

### 3.1 クラウドモデル

#### OpenAI Whisper API / gpt-4o-transcribe

| 項目 | Whisper API | gpt-4o-transcribe | gpt-4o-mini-transcribe |
|------|------------|-------------------|----------------------|
| **価格** | $0.006/分 | $0.006/分 | $0.003/分 |
| **精度（英語）** | WER 2.7%（クリーン音声） | Whisperより約50%低WER | 推奨モデル（2025/12以降） |
| **精度（日本語）** | CERベース評価、良好 | 日本語含む多言語改善 | - |
| **レイテンシ** | ~500ms | ~320ms | ~320ms |
| **リアルタイム** | 非対応 | Streaming対応 | Streaming対応 |
| **長所** | 安価、99言語対応、高精度 | 最高精度、低レイテンシ | 最安価、高精度 |
| **短所** | ネット接続必須、プライバシー懸念 | ネット接続必須 | ネット接続必須 |

#### Google Gemini Audio API

| 項目 | 内容 |
|------|------|
| **価格** | Gemini 3 Flash: $0.50入力/$3出力 per 1Mトークン（無料枠あり）、Pro: $2-4入力/$12-18出力 |
| **精度** | マルチモーダル理解に優れる |
| **レイテンシ** | Live APIでリアルタイム対応 |
| **特徴** | 話者分離、感情検出、タイムスタンプ付き分析 |
| **制限** | リアルタイム転写は非対応（Live APIは別機能）、音声専用APIではない |
| **日本語** | 対応 |

#### Anthropic Claude

| 項目 | 内容 |
|------|------|
| **現状** | 音声入力はモバイルアプリ（iOS/Android）で対応。専用の音声認識APIは未提供 |
| **価格** | 通常のチャットメッセージクォータ内 |
| **将来** | 2026年Q1にオフライン音声パック計画中（30秒以下の短いプロンプト用） |
| **音声入力向き** | 現時点では音声入力ツールのバックエンドとしては不適 |

### 3.2 ローカルモデル

#### Whisper.cpp

| 項目 | 内容 |
|------|------|
| **コスト** | 無料・オープンソース |
| **精度** | クリア音声で約96%、クラウド版と同等 |
| **日本語** | CERベース評価、99言語対応、日本語良好 |
| **レイテンシ** | Python版の2-10倍高速 |
| **リアルタイム** | 対応可能（stream機能） |
| **オフライン** | 完全対応 |
| **必要HW** | CPU動作可能。GPUで高速化。Apple Silicon推奨 |
| **長所** | 最も広く使われるローカル実装、C/C++で高速、多くのアプリの基盤 |
| **短所** | Swift/macOSとのインテグレーションに追加作業必要 |

#### WhisperKit

| 項目 | 内容 |
|------|------|
| **コスト** | 無料・オープンソース（Argmax開発） |
| **精度** | Whisper Large v3 Turboで最先端精度、gpt-4o-transcribeに匹敵 |
| **日本語** | Whisperモデルと同等 |
| **レイテンシ** | **平均0.45秒/ワード**、クラウドサービス（Fireworks）と同等速度 |
| **リアルタイム** | **対応**（ストリーミング、ワードタイムスタンプ、VAD） |
| **オフライン** | 完全対応 |
| **必要HW** | **Apple Silicon必須**（Neural Engine活用） |
| **長所** | Apple Neural Engine最適化、Swift Package、CoreML統合、WWDC 2025でApple公認 |
| **短所** | Apple Silicon限定、モデルダウンロード必要 |

**WWDC 2025での発展:** AppleがSpeechAnalyzerを導入し、WhisperKitとの統合を予定。ユーザーはArgmaxモデルダウンロード中にプリインストールのAppleモデルを利用可能に。

#### MLX Whisper / Lightning Whisper MLX

| 項目 | 内容 |
|------|------|
| **コスト** | 無料・オープンソース |
| **精度** | Whisperモデル準拠 |
| **レイテンシ** | Lightning版: **Whisper.cppの10倍高速、通常MLX Whisperの4倍高速** |
| **リアルタイム** | 対応可能 |
| **オフライン** | 完全対応 |
| **必要HW** | Apple Silicon必須（Metal GPU加速） |
| **長所** | Apple MLXフレームワーク活用、Pythonエコシステム、最高速の処理 |
| **短所** | Python依存、Swiftアプリへの統合に工夫必要 |

**新展開:**
- MLX Audio: TTS/STT/STSを包括的に対応するライブラリ
- MLX-Qwen3-ASR: Apple Silicon上でQwen3-ASRモデルをネイティブ実行（PyTorch/CUDA不要）

#### 日本語特化モデル: Kotoba-Whisper

| 項目 | 内容 |
|------|------|
| **コスト** | 無料・オープンソース（Hugging Face） |
| **精度** | **whisper-large-v3より日本語で高CER/WER性能**（ReazonSpeechデータセット） |
| **特徴** | 日本語に特化したファインチューニング済みモデル |
| **評価** | JSUT basic 5000、CommonVoice 8.0日本語サブセットで競争力のある結果 |

### 3.3 モデル比較サマリ

| モデル | 精度（英語） | 日本語 | レイテンシ | コスト | オフライン | リアルタイム |
|--------|-------------|--------|-----------|--------|-----------|-------------|
| gpt-4o-mini-transcribe | 最高 | 良好 | 320ms | $0.003/分 | x | o |
| gpt-4o-transcribe | 最高 | 改善 | 320ms | $0.006/分 | x | o |
| Whisper API | 高 | 良好 | 500ms | $0.006/分 | x | x |
| WhisperKit (large-v3-turbo) | 高 | 良好 | 450ms/word | 無料 | o | o |
| Lightning Whisper MLX | 高 | 良好 | 最速 | 無料 | o | o |
| Whisper.cpp | 高 | 良好 | 速 | 無料 | o | o |
| Kotoba-Whisper | - | **最高** | - | 無料 | o | - |
| Google Gemini | 高 | 良好 | 可変 | トークンベース | x | Live APIのみ |
| Deepgram Nova-3 | 高 | 限定 | 300ms | 有料 | x (on-prem可) | o |

---

## 4. 技術スタック調査

### 4.1 フレームワーク比較

#### Swift + SwiftUI（ネイティブ）

| 項目 | 評価 |
|------|------|
| **macOS API アクセス** | 最高。全API（マイク、アクセシビリティ、メニューバー、Neural Engine）にネイティブアクセス |
| **パフォーマンス** | 最高。メモリ使用量最小、起動速度最速 |
| **アプリサイズ** | 最小（数MB〜） |
| **開発速度** | macOS専用なら高速。SwiftUIのMenuBarExtra等で迅速開発 |
| **クロスプラットフォーム** | 非対応（macOS/iOS限定） |
| **WhisperKit統合** | **Swift Package で直接統合可能**（最大の利点） |
| **アクセシビリティAPI** | NSAccessibility経由で完全アクセス |
| **総合** | macOS専用ツールには最適解 |

#### Tauri 2 + React/Vue

| 項目 | 評価 |
|------|------|
| **macOS API アクセス** | プラグイン経由。マイクアクセスプラグイン、システムトレイ対応済み。アクセシビリティは要カスタム実装 |
| **パフォーマンス** | 良好。アイドル30-40MB RAM |
| **アプリサイズ** | 小さい（10MB未満） |
| **開発速度** | Webフロントエンド開発者なら高速。Rust知識が必要 |
| **クロスプラットフォーム** | Mac / Windows / Linux |
| **音声認識統合** | tauri-plugin-mic-recorder、tauri-plugin-audio-recorder利用可能 |
| **注意点** | macOS権限（Info.plist設定）に注意が必要 |
| **総合** | クロスプラットフォームなら有力候補 |

#### Electron + React/Vue

| 項目 | 評価 |
|------|------|
| **macOS API アクセス** | Node.js経由。マイクアクセス可能、アクセシビリティは限定的 |
| **パフォーマンス** | 低い。アイドル200-300MB RAM、起動1-2秒 |
| **アプリサイズ** | 大きい（100MB以上） |
| **開発速度** | Web開発者なら最速。最大のエコシステム |
| **クロスプラットフォーム** | Mac / Windows / Linux |
| **実績** | Slack、VS Code等の実績 |
| **総合** | リソース効率の観点から音声入力ツールには非推奨 |

#### PyQt6 / PySide6

| 項目 | 評価 |
|------|------|
| **macOS API アクセス** | PyObjC経由で一部アクセス可能。ネイティブ感は薄い |
| **パフォーマンス** | 中程度 |
| **アプリサイズ** | 中〜大（Pythonランタイム込み） |
| **開発速度** | Python MLエコシステムとの親和性が高い（whisper, mlx-whisper直接利用） |
| **クロスプラットフォーム** | Mac / Windows / Linux |
| **ライセンス** | PySide6: LGPL（商用利用可）、PyQt6: GPL or 商用ライセンス |
| **総合** | MLモデル統合重視なら選択肢だが、macOS統合は弱い |

### 4.2 技術スタック推奨マトリクス

| 優先事項 | 推奨スタック |
|----------|-------------|
| **macOS最適化・最高品質** | Swift + SwiftUI + WhisperKit |
| **クロスプラットフォーム・モダン** | Tauri 2 + React/Vue + whisper.cpp (Rust FFI) |
| **ML統合重視・プロトタイプ** | Python + PySide6 + mlx-whisper |
| **既存Webチーム活用** | Tauri 2 + React/Vue |

### 4.3 推奨アーキテクチャ（macOS専用の場合）

```
┌─────────────────────────────────────────┐
│            macOS Application            │
│  ┌──────────────┐  ┌────────────────┐   │
│  │  SwiftUI     │  │  MenuBarExtra  │   │
│  │  Settings    │  │  (Status Bar)  │   │
│  └──────────────┘  └────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │     Recording Manager            │   │
│  │  (AVAudioRecorder / AVCapture)   │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │     WhisperKit (Speech-to-Text)  │   │
│  │  ┌────────┐  ┌───────────────┐   │   │
│  │  │ VAD    │  │ Whisper Model │   │   │
│  │  └────────┘  └───────────────┘   │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │     Text Processor               │   │
│  │  (AI整形 / フィラー除去 / 句読点)  │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │     Text Insertion               │   │
│  │  (クリップボード / Accessibility) │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

---

## 5. 総合所見

### 5.1 市場の現状

- **ローカル処理がトレンド:** プライバシー意識の高まりにより、SuperWhisper、VoiceInk、Spokenly等のローカル処理ツールが急増
- **価格モデル:** 買い切り（VoiceInk $39）からサブスク（Wispr Flow $15/月）まで幅広い。買い切りモデルがユーザーに好評
- **オープンソース:** VoiceInkのオープンソース化は差別化要因として機能
- **クラウド vs ローカル:** Wispr Flowのクラウド依存はプライバシー面で批判を受けている

### 5.2 差別化の機会

1. **日本語特化:** Kotoba-Whisperの統合による日本語精度の大幅向上。現在、日本語に特化したMac音声入力ツールは少ない
2. **AI整形の高度化:** LLMによる文脈理解型のテキスト整形（現在のツールは基本的な句読点・フィラー除去が中心）
3. **開発者向け機能:** コード入力モード、ターミナルコマンド入力、IDE統合
4. **ハイブリッドモデル:** ローカル処理をデフォルトとしつつ、クラウドAPIをオプション提供
5. **適正価格:** VoiceInkの$39買い切りモデルが好評な市場で、競争力のある価格設定

### 5.3 技術推奨

**最適な組み合わせ:**
- **フレームワーク:** Swift + SwiftUI（macOS専用として最高のユーザー体験）
- **音声認識:** WhisperKit（Apple Silicon最適化、Swift Package直接統合、リアルタイム対応）
- **日本語強化:** Kotoba-Whisperモデルの統合検討
- **テキスト挿入:** クリップボード経由 + 復元機能をメイン、アクセシビリティAPIをオプション
- **AI整形（オプション）:** OpenAI API / ローカルLLM によるテキスト後処理

---

## Sources

### 既存ツール
- [SuperWhisper](https://superwhisper.com/)
- [SuperWhisper App Store](https://apps.apple.com/us/app/superwhisper/id6471464415)
- [Wispr Flow](https://wisprflow.ai)
- [Wispr Flow Review 2026](https://weesperneonflow.ai/en/blog/2026-02-09-wispr-flow-review-cloud-dictation-2026/)
- [Wispr Flow Pricing](https://www.eesel.ai/blog/wispr-flow-pricing)
- [MacWhisper (Gumroad)](https://goodsnooze.gumroad.com/l/macwhisper)
- [MacWhisper App Store](https://apps.apple.com/us/app/whisper-transcription/id1668083311)
- [Talon Voice](https://talonvoice.com/)
- [VoiceInk](https://tryvoiceink.com/)
- [VoiceInk GitHub](https://github.com/Beingpax/VoiceInk)
- [Spokenly](https://spokenly.app/)
- [Sotto](https://sotto.to)
- [VocaType](https://vocatype.com/)
- [Willow Voice](https://willowvoice.com/)

### モデル・技術
- [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)
- [Apple SpeechAnalyzer and WhisperKit](https://www.argmaxinc.com/blog/apple-and-argmax)
- [Lightning Whisper MLX](https://github.com/mustafaaljadery/lightning-whisper-mlx)
- [MLX Audio](https://github.com/Blaizzy/mlx-audio)
- [Kotoba-Whisper v1.0](https://huggingface.co/kotoba-tech/kotoba-whisper-v1.0)
- [OpenAI Whisper](https://github.com/openai/whisper)
- [OpenAI Next-gen Audio Models](https://openai.com/index/introducing-our-next-generation-audio-models/)
- [OpenAI API Pricing](https://platform.openai.com/docs/pricing)
- [Gemini Audio Understanding](https://ai.google.dev/gemini-api/docs/audio)
- [Whisper.cpp Review](https://tutorialswithai.com/tools/whisper-cpp/)

### 比較・レビュー
- [Best AI Dictation Apps for Mac: True Differentiators](https://afadingthought.substack.com/p/best-ai-dictation-tools-for-mac)
- [Best Dictation Apps for macOS 2026](https://www.macaiapps.com/blog/best-dictation-apps-for-macos/)
- [SuperWhisper Alternatives 2026](https://www.getvoibe.com/blog/superwhisper-alternatives/)
- [2025 Edge STT Benchmark](https://www.ionio.ai/blog/2025-edge-speech-to-text-model-benchmark-whisper-vs-competitors)
- [Best Open Source STT 2026](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [macOS Tahoe Voice Dictation](https://weesperneonflow.ai/en/blog/2025-10-27-voice-dictation-macos-tahoe-native-features-third-party-apps-2025/)

### 技術スタック
- [Tauri vs Electron Comparison](https://www.raftlabs.com/blog/tauri-vs-electron-pros-cons/)
- [Tauri System Tray](https://v2.tauri.app/learn/system-tray/)
- [SwiftUI MenuBarExtra](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
- [macOS Menu Bar App with Swift](https://capgemini.github.io/development/macos-development-with-swift/)
- [WhisperKit On-device Real-time ASR Paper](https://arxiv.org/html/2507.10860v1)
