# Mac用AI音声入力ツール 技術的実現可能性調査レポート

## 総合評価

全6項目について技術的に実現可能。Xcode IDEなしでSPMのみによるmacOSメニューバーアプリの構築、音声録音、グローバルホットキー、テキスト挿入、Whisper/Gemini API連携のすべてが、Swift + Command Line Toolsで実装できる。

---

## 1. Swift Package ManagerでmacOS GUIアプリの構築

### 実現可能性: 完全に可能

Xcode IDEを使わず、Command Line Toolsのみで SwiftUI/AppKit ベースのmacOSアプリケーションを構築できる。

### Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioInput",
    platforms: [
        .macOS(.v13)  // MenuBarExtra は macOS 13+ 必須
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AudioInput",
            dependencies: [],
            resources: [
                .copy("Resources/Info.plist")
            ]
        ),
    ]
)
```

### main.swift - AppKitベースの起動方法（SPM対応）

SPMで `@main` App プロトコルを直接使うには制限があるため、AppKit経由で起動するのが確実な方法:

```swift
import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // メニューバーアイテムの作成
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Audio Input")
            button.action = #selector(togglePopover)
        }

        // ポップオーバーの設定
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 200)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView())
    }

    @objc func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Dockアイコンを非表示（LSUIElementの代替）
NSApp.setActivationPolicy(.accessory)

app.run()
```

### @main App プロトコルを使う方法（macOS 13+）

`@main` を使う場合、main.swift を使わず、App.swift に直接記述する:

```swift
import SwiftUI

@main
struct AudioInputApp: App {
    var body: some Scene {
        MenuBarExtra("Audio Input", systemImage: "mic.fill") {
            ContentView()
                .frame(width: 300, height: 200)
        }
        .menuBarExtraStyle(.window)
    }
}
```

**注意**: SPMの executableTarget で `@main` を使う場合、main.swift ファイルが存在してはならない。Entry point の競合が発生する。

### .app バンドルの作成スクリプト

```bash
#!/bin/bash
APP_NAME="AudioInput"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

# ビルド
swift build -c release

# バンドル構造の作成
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# バイナリのコピー
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Info.plist の作成
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.nyosegawa.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>音声入力のためにマイクを使用します</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>テキスト入力のためにアプリケーションを制御します</string>
</dict>
</plist>
EOF

# 実行権限
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "Created ${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}"
```

### 重要なポイント

- **LSUIElement**: `<true/>` に設定するとDockアイコンが非表示になる。コードからは `NSApp.setActivationPolicy(.accessory)` でも同等の効果
- **コード署名なし実行**: `swift build` で生成したバイナリはそのまま実行可能。Gatekeeperの警告は `xattr -cr AudioInput.app` で回避
- **MenuBarExtra**: macOS 13 (Ventura) 以降のSwiftUI限定。それ以前は NSStatusBar APIを使用

### 参考情報

- [The.Swift.Dev - SPMだけでmacOSアプリ構築](https://theswiftdev.com/how-to-build-macos-apps-using-only-the-swift-package-manager/)
- [objc.io - Xcode ProjectなしでSwiftUI](https://www.objc.io/blog/2020/05/19/swiftui-without-an-xcodeproj/)
- [Swift Forums - SwiftPMだけでSwiftUIアプリ開発の議論](https://forums.swift.org/t/is-it-possible-to-developer-a-swiftui-app-using-only-swiftpm/71755)
- [Swift Bundler - SPMベースのアプリバンドラー](https://swiftbundler.dev/)
- [Nil Coalescing - MenuBarExtraアプリ構築](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
- [Apple Developer - LSUIElementドキュメント](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)

---

## 2. macOS Audio Recording API

### 実現可能性: 完全に可能

### AVAudioEngine vs AVAudioRecorder

| 特性 | AVAudioEngine | AVAudioRecorder |
|------|-------------|-----------------|
| リアルタイムバッファアクセス | 可能（installTap） | 不可 |
| 音声レベルメーター | バッファから計算 | meteringEnabled で取得 |
| フォーマット変換 | AVAudioConverter | 設定時に指定 |
| 柔軟性 | 高い | 低い（録音専用） |
| 適用シーン | リアルタイム処理 | 単純な録音 |

**推奨: AVAudioEngine** - リアルタイム音声バッファの取得が可能で、音声レベルメーターの実装や録音中のストリーミング送信に対応。

### 完全な録音実装

```swift
import AVFoundation

class AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isRecording = false

    // 音声レベルコールバック
    var onAudioLevel: ((Float) -> Void)?

    // マイクパーミッションのリクエスト
    func requestPermission() async -> Bool {
        // macOS では AVCaptureDevice を使用
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // 録音開始
    func startRecording(to url: URL) throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // WAV形式で録音する設定
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,  // Whisper API推奨
            AVNumberOfChannelsKey: 1,   // モノラル
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        // 出力形式の作成
        guard let outputFormat = AVAudioFormat(settings: settings) else {
            throw RecordingError.formatError
        }

        // フォーマットコンバーターの作成
        guard let converter = AVAudioConverter(from: recordingFormat, to: outputFormat) else {
            throw RecordingError.converterError
        }

        // 出力ファイルの作成
        audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // 入力タップのインストール
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) {
            [weak self] (buffer, time) in
            guard let self = self else { return }

            // 音声レベルの計算
            let level = self.calculateAudioLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.onAudioLevel?(level)
            }

            // フォーマット変換とファイル書き込み
            let ratio = outputFormat.sampleRate / recordingFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            var gotData = false
            converter.convert(to: outputBuffer, error: &error) { _, status in
                if gotData {
                    status.pointee = .noDataNow
                    return nil
                }
                gotData = true
                status.pointee = .haveData
                return buffer
            }

            do {
                try self.audioFile?.write(from: outputBuffer)
            } catch {
                print("Error writing audio: \(error)")
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    // 録音停止
    func stopRecording() -> URL? {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        let url = audioFile?.url
        audioFile = nil
        isRecording = false
        return url
    }

    // 音声レベルの計算（RMS）
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<channelDataCount {
            sum += channelDataValue[i] * channelDataValue[i]
        }

        let rms = sqrt(sum / Float(channelDataCount))
        // dBに変換（-160 ~ 0 の範囲にクランプ）
        let db = 20 * log10(max(rms, 0.000001))
        // 0~1の範囲に正規化
        return max(0, min(1, (db + 60) / 60))
    }
}

enum RecordingError: Error {
    case formatError
    case converterError
    case permissionDenied
}
```

### m4a形式での録音

```swift
// m4a(AAC)形式で録音する場合の設定
let m4aSettings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 44100.0,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    AVEncoderBitRateKey: 128000
]

// AVAudioFileの作成時に拡張子を .m4a にする
let m4aURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("recording.m4a")
```

### Info.plist でのパーミッション設定

```xml
<key>NSMicrophoneUsageDescription</key>
<string>音声入力のためにマイクを使用します</string>
```

Hardened Runtimeを使用する場合のentitlements:

```xml
<key>com.apple.security.device.microphone</key>
<true/>
```

### 参考情報

- [Reiterate Blog - AVAudioEngineでWAV録音](https://blog.reiterate.app/software/2022/03/11/acknowledgement-part-7/)
- [Apple Developer - AVAudioEngine Forum](https://developer.apple.com/forums/tags/avaudioengine)
- [Hacking with Swift - AVAudioRecorder](https://www.hackingwithswift.com/read/33/2/recording-from-the-microphone-with-avaudiorecorder)
- [Apple Developer - requestRecordPermission](https://developer.apple.com/documentation/avfaudio/avaudiosession/requestrecordpermission(_:))

---

## 3. Global Hotkey Registration

### 実現可能性: 完全に可能

3つのアプローチがあり、それぞれ特性が異なる。

### 方法1: NSEvent.addGlobalMonitorForEvents（最も簡単）

```swift
import AppKit

class GlobalHotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var onHotkeyPressed: (() -> Void)?

    func register() {
        // グローバルモニター（他アプリがフォーカス中）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // ローカルモニター（自アプリがフォーカス中）
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Ctrl + Shift + Space を検出
        let requiredFlags: NSEvent.ModifierFlags = [.control, .shift]
        if event.modifierFlags.contains(requiredFlags) &&
           event.keyCode == 49 { // 49 = Space
            onHotkeyPressed?()
        }
    }

    func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
```

**制限**: `addGlobalMonitorForEvents` はイベントを読み取るだけで、消費（swallow）できない。Input Monitoring権限が必要。

### 方法2: CGEvent Tap（イベント消費可能、より強力）

```swift
import Cocoa

class CGEventHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHotkeyPressed: (() -> Void)?

    func start() -> Bool {
        // アクセシビリティ権限の確認
        let trusted = CGPreflightListenEventAccess()
        if !trusted {
            CGRequestListenEventAccess()
            return false
        }

        // イベントタップの作成
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue)

        // selfをポインタとして渡す
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // イベントを消費可能
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<CGEventHotkeyManager>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            print("Failed to create event tap. Accessibility permission required.")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Ctrl + Shift + Space (keyCode 49) を検出
            if keyCode == 49 &&
               flags.contains(.maskControl) &&
               flags.contains(.maskShift) {
                DispatchQueue.main.async {
                    self.onHotkeyPressed?()
                }
                return nil  // イベントを消費（他アプリに渡さない）
            }
        }

        return Unmanaged.passUnretained(event)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
```

**必要な権限**: Accessibility（アクセシビリティ）権限。`defaultTap` はアクセシビリティ、`listenOnly` はInput Monitoring権限が必要。

### 方法3: RegisterEventHotKey（Carbon API、App Store互換）

```swift
import Carbon

class CarbonHotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    var onHotkeyPressed: (() -> Void)?

    func register() {
        // ホットキーIDの定義
        var hotkeyID = EventHotKeyID()
        hotkeyID.signature = OSType(0x4154_4950) // "ATIP" 任意の4文字
        hotkeyID.id = 1

        // イベントタイプの定義
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // イベントハンドラのインストール
        let handler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<CarbonHotkeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()
            manager.onHotkeyPressed?()
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        // Ctrl + Shift + Space の登録
        // Space = kVK_Space = 49
        let modifiers = UInt32(controlKey | shiftKey)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
```

### 推奨ライブラリ: sindresorhus/KeyboardShortcuts

SPMで導入可能。RegisterEventHotKey をラップしたモダンなSwift API:

```swift
// Package.swift に追加
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")

// 使用例
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

// ハンドラの登録
KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
    // 録音開始/停止
}
```

### 各方法の比較

| 方法 | イベント消費 | 必要権限 | App Store | 推奨度 |
|------|------------|----------|-----------|-------|
| NSEvent.addGlobalMonitor | 不可 | Input Monitoring | 非対応 | 低 |
| CGEvent Tap | 可能 | Accessibility | 非対応 | 中 |
| RegisterEventHotKey | N/A | なし | 対応 | 高 |
| KeyboardShortcuts パッケージ | N/A | なし | 対応 | 最高 |

### macOS 15の注意事項

macOS 15 で、Option単独またはOption+Shiftのみの修飾キーを使ったグローバルショートカットが動作しないバグが報告されている。Ctrl や Cmd を含む組み合わせを推奨。

### 参考情報

- [Apple Developer Forum - Global Hotkey実装](https://developer.apple.com/forums/thread/735223)
- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [GitHub - AeroSpace CGEvent Tap調査](https://github.com/nikitabobko/AeroSpace/issues/1012)
- [alt-tab-macos KeyboardEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/events/KeyboardEvents.swift)
- [macOS 15 ホットキーバグ報告](https://github.com/feedback-assistant/reports/issues/552)
- [Gist - CGEventSupervisor実装例](https://gist.github.com/stephancasas/fd27ebcd2a0e36f3e3f00109d70abcdc)

---

## 4. テキスト挿入方法

### 実現可能性: 完全に可能（サンドボックス外）

### 方法1: NSPasteboard + Cmd+V シミュレーション（推奨）

日本語テキストを含むUnicode文字列を確実に挿入できる最も実用的な方法:

```swift
import AppKit

class TextInserter {

    /// クリップボード経由でテキストを挿入（推奨方法）
    func insertViaPaste(_ text: String) {
        // 1. 現在のクリップボード内容を保存
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        // 2. テキストをクリップボードに設定
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Cmd+V を送信
        simulatePaste()

        // 4. 少し待ってからクリップボードを復元
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let previous = previousContents {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    /// Cmd+V キーストロークをシミュレーション
    private func simulatePaste() {
        let vKeyCode: CGKeyCode = 9  // 'v' のキーコード

        // Key Down (Cmd + V)
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                     virtualKey: vKeyCode,
                                     keyDown: true) else { return }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)

        // Key Up
        guard let keyUp = CGEvent(keyboardEventSource: nil,
                                   virtualKey: vKeyCode,
                                   keyDown: false) else { return }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

### 方法2: CGEvent キーストロークシミュレーション

文字単位でキーを送信。ASCII文字には有効だが、日本語には不向き:

```swift
import AppKit

extension TextInserter {

    /// 文字列を1文字ずつキーストロークで入力
    func typeString(_ text: String) {
        for character in text {
            typeCharacter(character)
            usleep(50_000) // 50ms 待機
        }
    }

    /// Unicode文字をCGEventで入力
    private func typeCharacter(_ char: Character) {
        let utf16 = Array(String(char).utf16)

        for codeUnit in utf16 {
            guard let keyDown = CGEvent(keyboardEventSource: nil,
                                         virtualKey: 0,
                                         keyDown: true) else { continue }
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: [codeUnit])
            keyDown.post(tap: .cgAnnotatedSessionEventTap)

            guard let keyUp = CGEvent(keyboardEventSource: nil,
                                       virtualKey: 0,
                                       keyDown: false) else { continue }
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: [codeUnit])
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
```

**注意**: `keyboardSetUnicodeString` で日本語文字をCGEventに直接設定する方法も存在するが、IMEの状態によって動作が不安定になる場合がある。

### 方法3: Accessibility API (AXUIElement)

フォーカスされたテキストフィールドの値を直接設定:

```swift
import ApplicationServices

extension TextInserter {

    /// AXUIElement経由でテキストを挿入
    func insertViaAccessibility(_ text: String) -> Bool {
        // フォーカスされたアプリケーションを取得
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // フォーカスされた要素を取得
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success,
              let element = focusedElement else {
            return false
        }

        // 現在の値を取得
        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            &currentValue
        )

        // 選択範囲を取得してテキストを挿入
        var selectedRange: AnyObject?
        AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        // 選択テキストを置換
        AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        return true
    }
}
```

### 各方法の比較

| 方法 | 日本語対応 | 速度 | 信頼性 | 必要権限 |
|------|-----------|------|--------|----------|
| NSPasteboard + Cmd+V | 完全 | 高速 | 高い | Accessibility |
| CGEvent keystroke | 限定的 | 遅い | 中程度 | Accessibility |
| CGEvent Unicode | 対応 | 遅い | IME依存 | Accessibility |
| AXUIElement | 完全 | 高速 | アプリ依存 | Accessibility |

### 推奨

**NSPasteboard + Cmd+V 方式**を推奨。理由:
- 日本語（Unicode全般）を完全にサポート
- 高速で確実
- クリップボード内容の保存・復元が可能
- ほぼすべてのアプリケーションで動作

### 参考情報

- [Igor Kulman - Auto-Type実装](https://blog.kulman.sk/implementing-auto-type-on-macos/)
- [Apple Developer Forum - ペースト送信](https://developer.apple.com/forums/thread/61387)
- [Apple Developer Forum - CGEventでペーストシミュレーション](https://developer.apple.com/forums/thread/659804)
- [Hacking with Swift - テキスト入力](https://www.hackingwithswift.com/forums/macos/how-can-i-programmatically-enter-text-to-an-arbitrary-application-first-responder/1612)
- [GitHub Gist - Paste as keystrokes](https://gist.github.com/sscotth/310db98e7c4ec74e21819806dc527e97)

---

## 5. OpenAI Whisper API Integration in Swift

### 実現可能性: 完全に可能

### URLSession を使った multipart/form-data リクエスト

```swift
import Foundation

struct WhisperTranscriptionResponse: Codable {
    let text: String
}

struct WhisperErrorResponse: Codable {
    let error: WhisperError

    struct WhisperError: Codable {
        let message: String
        let type: String
    }
}

class WhisperAPI {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// 音声ファイルを文字起こし
    func transcribe(
        audioURL: URL,
        model: String = "whisper-1",
        language: String? = "ja",
        prompt: String? = nil,
        responseFormat: String = "json"
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        // multipart body の構築
        let audioData = try Data(contentsOf: audioURL)
        let fileName = audioURL.lastPathComponent
        let mimeType = mimeType(for: audioURL)

        var body = Data()

        // file パラメータ
        body.appendMultipart(boundary: boundary, name: "file",
                            fileName: fileName, mimeType: mimeType,
                            data: audioData)

        // model パラメータ
        body.appendMultipart(boundary: boundary, name: "model", value: model)

        // language パラメータ（オプション）
        if let language = language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // prompt パラメータ（オプション）
        if let prompt = prompt {
            body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        }

        // response_format パラメータ
        body.appendMultipart(boundary: boundary, name: "response_format",
                            value: responseFormat)

        // 終了バウンダリ
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // リクエスト送信
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(
                WhisperErrorResponse.self, from: data
            ) {
                throw WhisperAPIError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.error.message
                )
            }
            throw WhisperAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        if responseFormat == "text" {
            return String(data: data, encoding: .utf8) ?? ""
        }

        let result = try JSONDecoder().decode(
            WhisperTranscriptionResponse.self, from: data
        )
        return result.text
    }

    /// gpt-4o-transcribe モデルを使用（高精度・ストリーミング対応）
    func transcribeWithGPT4o(
        audioURL: URL,
        language: String? = "ja"
    ) async throws -> String {
        return try await transcribe(
            audioURL: audioURL,
            model: "gpt-4o-transcribe",
            language: language,
            responseFormat: "json"
        )
    }

    // MIME type の判定
    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        case "webm": return "audio/webm"
        default: return "audio/wav"
        }
    }
}

// Data拡張: multipart構築ヘルパー
extension Data {
    mutating func appendMultipart(boundary: String, name: String,
                                   value: String) {
        let field = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            + "\(value)\r\n"
        self.append(field.data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String,
                                   fileName: String, mimeType: String,
                                   data: Data) {
        var header = "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(name)\"; "
        header += "filename=\"\(fileName)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        self.append(header.data(using: .utf8)!)
        self.append(data)
        self.append("\r\n".data(using: .utf8)!)
    }
}

enum WhisperAPIError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}
```

### 利用可能なモデル

| モデル | 特徴 | ストリーミング |
|-------|------|-------------|
| whisper-1 | Whisper V2ベース、安定 | 非対応 |
| gpt-4o-transcribe | 高精度、GPT-4oベース | 対応（SSE） |
| gpt-4o-mini-transcribe | 軽量・高速 | 対応（SSE） |

### ストリーミング対応（gpt-4o-transcribeのみ）

```swift
extension WhisperAPI {
    /// SSEストリーミングで文字起こし
    func transcribeStreaming(
        audioURL: URL,
        onPartialResult: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "file",
                            fileName: audioURL.lastPathComponent,
                            mimeType: mimeType(for: audioURL),
                            data: audioData)
        body.appendMultipart(boundary: boundary, name: "model",
                            value: "gpt-4o-transcribe")
        body.appendMultipart(boundary: boundary, name: "stream", value: "true")
        body.appendMultipart(boundary: boundary, name: "language", value: "ja")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // URLSessionでSSEを受信
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WhisperAPIError.invalidResponse
        }

        var fullText = ""
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if jsonString == "[DONE]" { break }

                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let delta = json["delta"] as? String {
                    fullText += delta
                    onPartialResult(fullText)
                }
            }
        }
        onComplete(fullText)
    }
}
```

### サポートされるオーディオ形式

flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, webm

### 参考情報

- [OpenAI API Reference - Audio Transcription](https://platform.openai.com/docs/api-reference/audio/createTranscription)
- [OpenAI Speech to Text ガイド](https://platform.openai.com/docs/guides/speech-to-text)
- [MacPaw/OpenAI Swift パッケージ](https://github.com/MacPaw/OpenAI)
- [The.Swift.Dev - Multipart Upload](https://theswiftdev.com/easy-multipart-file-upload-for-swift/)

---

## 6. Gemini Audio API Integration

### 実現可能性: 完全に可能

### Gemini API での音声処理

Gemini はネイティブに音声を理解でき、文字起こし専用ではなくマルチモーダルな音声理解が可能。

### 方法1: インライン音声（Base64エンコード、20MB以下）

```swift
import Foundation

struct GeminiResponse: Codable {
    let candidates: [Candidate]

    struct Candidate: Codable {
        let content: Content
    }

    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String?
    }
}

class GeminiAudioAPI {
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    // 注意: Gemini 2.0 Flash は 2026年3月31日に廃止予定
    // gemini-2.5-flash-lite に移行を推奨
    private var model = "gemini-2.5-flash-lite"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// インライン音声データで文字起こし
    func transcribe(audioURL: URL, language: String = "ja") async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        let mimeType = self.mimeType(for: audioURL)

        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt: String
        if language == "ja" {
            prompt = "この音声を正確に日本語で文字起こししてください。句読点も適切に入れてください。音声の内容のみを返し、説明や注釈は不要です。"
        } else {
            prompt = "Transcribe this audio accurately. Return only the transcription text without any explanation."
        }

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": mimeType,
                                "data": base64Audio
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 8192
            ]
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiAPIError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: errorText
            )
        }

        let geminiResponse = try JSONDecoder().decode(
            GeminiResponse.self, from: data
        )

        return geminiResponse.candidates.first?.content.parts
            .compactMap { $0.text }
            .joined(separator: " ") ?? ""
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mp3"
        case "m4a": return "audio/mp4"
        case "aac": return "audio/aac"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        case "aiff": return "audio/aiff"
        default: return "audio/wav"
        }
    }
}

enum GeminiAPIError: Error, LocalizedError {
    case httpError(statusCode: Int, message: String)
    case uploadFailed(message: String)
    case noTranscription

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "Gemini API error (\(code)): \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .noTranscription:
            return "No transcription returned"
        }
    }
}
```

### 方法2: File API を使った大容量ファイル（20MB超）

```swift
extension GeminiAudioAPI {

    /// File APIを使って音声をアップロードしてから文字起こし
    func transcribeLargeFile(audioURL: URL, language: String = "ja") async throws -> String {
        // Step 1: ファイルアップロードの開始（resumable upload）
        let audioData = try Data(contentsOf: audioURL)
        let mimeType = self.mimeType(for: audioURL)

        // アップロード初期化
        let initURL = URL(string: "\(baseURL)/files?key=\(apiKey)")!
        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "POST"
        initRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        initRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        initRequest.setValue("\(audioData.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        initRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let metadata = ["file": ["display_name": audioURL.lastPathComponent]]
        initRequest.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (_, initResponse) = try await URLSession.shared.data(for: initRequest)

        // アップロードURLの取得
        guard let httpResponse = initResponse as? HTTPURLResponse,
              let uploadURL = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL") else {
            throw GeminiAPIError.uploadFailed(message: "Failed to get upload URL")
        }

        // Step 2: ファイルデータのアップロード
        var uploadRequest = URLRequest(url: URL(string: uploadURL)!)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.httpBody = audioData

        let (uploadData, _) = try await URLSession.shared.data(for: uploadRequest)

        // ファイルURIの取得
        guard let uploadResult = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let file = uploadResult["file"] as? [String: Any],
              let fileURI = file["uri"] as? String else {
            throw GeminiAPIError.uploadFailed(message: "Failed to parse upload response")
        }

        // Step 3: 文字起こしリクエスト
        let generateURL = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")!
        var generateRequest = URLRequest(url: generateURL)
        generateRequest.httpMethod = "POST"
        generateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = language == "ja"
            ? "この音声を正確に日本語で文字起こししてください。句読点も適切に入れてください。音声の内容のみを返してください。"
            : "Transcribe this audio accurately. Return only the transcription text."

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "file_data": [
                                "mime_type": mimeType,
                                "file_uri": fileURI
                            ]
                        ]
                    ]
                ]
            ]
        ]

        generateRequest.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody
        )

        let (resultData, _) = try await URLSession.shared.data(for: generateRequest)

        let geminiResponse = try JSONDecoder().decode(
            GeminiResponse.self, from: resultData
        )

        return geminiResponse.candidates.first?.content.parts
            .compactMap { $0.text }
            .joined(separator: " ") ?? ""
    }
}
```

### Gemini API の仕様

| 項目 | 詳細 |
|------|------|
| トークンレート | 32トークン/秒 |
| 最大音声長 | 9.5時間（プロンプト全体で） |
| ダウンサンプリング | 16 Kbps |
| マルチチャンネル | 自動的にモノラルに統合 |
| インラインデータ上限 | 20MB |
| File API上限 | 2GB |

### サポート音声フォーマット

WAV, MP3, AIFF, AAC, OGG Vorbis, FLAC

### 日本語精度について

Geminiは多言語モデルであり日本語をネイティブにサポートしている。ただし、専用の音声認識モデル（Whisperなど）と比較すると:
- Geminiは「音声理解」が得意（要約、質問応答）
- 厳密な逐語文字起こしはWhisperが優位
- プロンプトで出力フォーマットを制御可能（Geminiの利点）
- Geminiは音声中の話者区別やノイズ対応で柔軟

### モデル選択の注意

- `gemini-2.0-flash` と `gemini-2.0-flash-lite` は **2026年3月31日に廃止予定**
- `gemini-2.5-flash-lite` への移行を推奨
- `gemini-2.5-flash` のNative Audio が一般提供開始済み

### 参考情報

- [Gemini API Audio Understanding ドキュメント](https://ai.google.dev/gemini-api/docs/audio)
- [Gemini by Example - Audio Transcription](https://geminibyexample.com/010-audio-transcription/)
- [Google Cloud Blog - Gemini音声文字起こし](https://cloud.google.com/blog/topics/partners/how-partners-unlock-scalable-audio-transcription-with-gemini/)
- [Gemini 2.5 Native Audio アップデート](https://blog.google/products/gemini/gemini-audio-model-updates/)

---

## 実装アーキテクチャ提案

上記の調査結果を踏まえた推奨アーキテクチャ:

```
AudioInput.app/
  Contents/
    MacOS/
      AudioInput          # swift build で生成されたバイナリ
    Info.plist            # LSUIElement=true, NSMicrophoneUsageDescription
    Resources/
      (アイコン等)

Sources/AudioInput/
  main.swift              # NSApplication起動、NSStatusBar設定
  App/
    AppDelegate.swift     # メニューバーUI、ライフサイクル管理
    ContentView.swift     # SwiftUI ポップオーバー UI
  Audio/
    AudioRecorder.swift   # AVAudioEngine録音（16kHz WAV）
  Hotkey/
    HotkeyManager.swift   # CGEvent Tap or KeyboardShortcuts
  TextInsert/
    TextInserter.swift    # NSPasteboard + Cmd+V
  API/
    WhisperClient.swift   # OpenAI Whisper API (URLSession)
    GeminiClient.swift    # Gemini Audio API (URLSession)
  Config/
    Settings.swift        # API Key管理、設定

Package.swift
build.sh                  # .appバンドル作成スクリプト
```

### 処理フロー

1. ユーザーがグローバルホットキー（例: Ctrl+Shift+Space）を押す
2. AudioRecorder が録音開始（AVAudioEngine、16kHz WAV）
3. 音声レベルメーターをUIに表示
4. もう一度ホットキーを押すか、無音検出で録音停止
5. WAVファイルを Whisper API または Gemini API に送信
6. 文字起こし結果を NSPasteboard + Cmd+V でアクティブアプリに挿入
7. クリップボードを元の状態に復元
