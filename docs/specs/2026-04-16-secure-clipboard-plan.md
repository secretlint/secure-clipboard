# SecureClipboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOSメニューバー常駐アプリで、クリップボードにコピーされたテキスト・画像からシークレットを自動検出しマスクする。

**Architecture:** SwiftUIメニューバーアプリがNSPasteboardをポーリング監視し、変更検知時にsecretlintバイナリ（Bunシングルバイナリ）をサブプロセスで呼び出す。テキストは`--format=mask-result`で直接マスク済み出力を取得、画像はVision frameworkでOCR後にスキャンし検出時は赤塗り画像で上書き。

**Tech Stack:** Swift, SwiftUI, AppKit (NSPasteboard), Vision framework, secretlint binary (Bun)

---

## File Structure

```
SecureClipboard/
├── SecureClipboard.xcodeproj/
├── SecureClipboard/
│   ├── SecureClipboardApp.swift          # App entry, menu bar setup
│   ├── ClipboardMonitor.swift            # NSPasteboard polling, change detection
│   ├── SecretScanner.swift               # secretlint binary subprocess execution
│   ├── ClipboardRewriter.swift           # Clipboard overwrite logic (text + image)
│   ├── ImageSecretDetector.swift         # Vision OCR + image redaction
│   ├── StatusState.swift                 # Observable state for menu bar icon/status
│   ├── MenuBarView.swift                 # Menu bar UI (toggle, history, raw copy)
│   ├── NotificationManager.swift         # macOS notification handling
│   ├── Resources/
│   │   ├── secretlint                    # secretlint binary (darwin-arm64)
│   │   └── secretlintrc.json            # Default config (preset-recommend)
│   └── Info.plist
├── SecureClipboardTests/
│   ├── SecretScannerTests.swift
│   ├── ClipboardRewriterTests.swift
│   ├── ClipboardMonitorTests.swift
│   └── ImageSecretDetectorTests.swift
├── scripts/
│   └── download-secretlint.sh            # Download secretlint binary for build
└── docs/
    └── specs/
```

---

### Task 1: Xcodeプロジェクトのセットアップ

**Files:**
- Create: `SecureClipboard/SecureClipboardApp.swift`
- Create: `scripts/download-secretlint.sh`
- Create: `SecureClipboard/Resources/secretlintrc.json`

- [ ] **Step 1: Xcodeプロジェクトを作成**

```bash
mkdir -p SecureClipboard SecureClipboardTests scripts
```

Swift Package Manager (SPM) ベースのプロジェクトとして構成する。`Package.swift` を使用:

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureClipboard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SecureClipboard",
            path: "SecureClipboard",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "SecureClipboardTests",
            dependencies: ["SecureClipboard"],
            path: "SecureClipboardTests"
        )
    ]
)
```

- [ ] **Step 2: 最小限のアプリエントリポイントを作成**

```swift
// SecureClipboard/SecureClipboardApp.swift
import SwiftUI

@main
struct SecureClipboardApp: App {
    var body: some Scene {
        MenuBarExtra("SecureClipboard", systemImage: "lock.shield") {
            Text("SecureClipboard")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 3: デフォルトのsecretlint設定ファイルを作成**

```json
// SecureClipboard/Resources/secretlintrc.json
{
    "rules": [
        {
            "id": "@secretlint/secretlint-rule-preset-recommend"
        }
    ]
}
```

- [ ] **Step 4: secretlintバイナリダウンロードスクリプトを作成**

```bash
#!/usr/bin/env bash
# scripts/download-secretlint.sh
set -euo pipefail

VERSION="${1:?Usage: download-secretlint.sh <version>}"
PLATFORM="darwin-arm64"
BINARY_NAME="secretlint-${VERSION}-${PLATFORM}"
URL="https://github.com/secretlint/secretlint/releases/download/v${VERSION}/${BINARY_NAME}"
DEST="SecureClipboard/Resources/secretlint"

echo "Downloading secretlint ${VERSION} for ${PLATFORM}..."
curl -fSL "${URL}" -o "${DEST}"
chmod +x "${DEST}"
echo "Downloaded to ${DEST}"
```

- [ ] **Step 5: secretlintバイナリをダウンロードしてビルド確認**

```bash
chmod +x scripts/download-secretlint.sh
# secretlintの最新バージョンを確認
gh release list -R secretlint/secretlint --limit 1
# ダウンロード
bash scripts/download-secretlint.sh <version>
# ビルド確認
swift build
```

- [ ] **Step 6: コミット**

```bash
git add Package.swift SecureClipboard/ SecureClipboardTests/ scripts/ .gitignore
git commit -m "feat: scaffold SecureClipboard macOS menu bar app"
```

---

### Task 2: SecretScanner — secretlintバイナリ連携

**Files:**
- Create: `SecureClipboard/SecretScanner.swift`
- Create: `SecureClipboardTests/SecretScannerTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// SecureClipboardTests/SecretScannerTests.swift
import Testing
@testable import SecureClipboard

@Test func scanTextWithNoSecret() async throws {
    let scanner = SecretScanner()
    let result = try await scanner.scan(text: "hello world")
    #expect(result.hasSecrets == false)
    #expect(result.maskedText == "hello world")
}

@Test func scanTextWithAWSKey() async throws {
    let scanner = SecretScanner()
    // AWSアクセスキーのダミー（AKIA + 16文字の英数字）
    let secretText = "my key is AKIAIOSFODNN7EXAMPLE"
    let result = try await scanner.scan(text: secretText)
    #expect(result.hasSecrets == true)
    #expect(result.maskedText.contains("AKIAIOSFODNN7EXAMPLE") == false)
    #expect(result.maskedText.contains("***") || result.maskedText.contains("*"))
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
swift test --filter SecretScannerTests
```

Expected: コンパイルエラー（SecretScanner未定義）

- [ ] **Step 3: SecretScannerを実装**

```swift
// SecureClipboard/SecretScanner.swift
import Foundation

struct ScanResult {
    let hasSecrets: Bool
    let maskedText: String
    let originalText: String
}

actor SecretScanner {
    private let binaryPath: String
    private let configJSON: String

    init() {
        // Bundleからsecretlintバイナリのパスを取得
        if let resourcePath = Bundle.main.resourcePath {
            self.binaryPath = "\(resourcePath)/Resources/secretlint"
        } else {
            self.binaryPath = "secretlint"
        }

        // デフォルト設定
        self.configJSON = """
        {"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}
        """
    }

    init(binaryPath: String, configJSON: String? = nil) {
        self.binaryPath = binaryPath
        self.configJSON = configJSON ?? """
        {"rules":[{"id":"@secretlint/secretlint-rule-preset-recommend"}]}
        """
    }

    func scan(text: String) async throws -> ScanResult {
        let maskedText = try await runSecretlint(input: text, format: "mask-result")
        let hasSecrets = maskedText != text
        return ScanResult(
            hasSecrets: hasSecrets,
            maskedText: maskedText,
            originalText: text
        )
    }

    private func runSecretlint(input: String, format: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "--stdinFileName", "clipboard.txt",
            "--format", format,
            "--secretlintrcJSON", configJSON
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let inputData = Data(input.utf8)
        inputPipe.fileHandleForWriting.write(inputData)
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? input

        // exit code 0 = no secrets, 1 = secrets found (both are valid)
        // exit code 2+ = error
        if process.terminationStatus > 1 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SecretScannerError.scanFailed(errorOutput)
        }

        return output
    }
}

enum SecretScannerError: Error {
    case scanFailed(String)
}
```

- [ ] **Step 4: テストを実行して通ることを確認**

```bash
swift test --filter SecretScannerTests
```

Expected: 2テスト PASS

- [ ] **Step 5: コミット**

```bash
git add SecureClipboard/SecretScanner.swift SecureClipboardTests/SecretScannerTests.swift
git commit -m "feat: add SecretScanner with secretlint binary integration"
```

---

### Task 3: ClipboardRewriter — クリップボード書き換え

**Files:**
- Create: `SecureClipboard/ClipboardRewriter.swift`
- Create: `SecureClipboardTests/ClipboardRewriterTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// SecureClipboardTests/ClipboardRewriterTests.swift
import Testing
import AppKit
@testable import SecureClipboard

@Test func rewriteTextUpdatesClipboard() {
    let rewriter = ClipboardRewriter()
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("original text", forType: .string)

    let changeCount = rewriter.rewriteText("masked text")

    let result = pasteboard.string(forType: .string)
    #expect(result == "masked text")
    #expect(changeCount == pasteboard.changeCount)
}

@Test func rewriteImageUpdatesClipboard() {
    let rewriter = ClipboardRewriter()
    let pasteboard = NSPasteboard.general

    // 10x10の赤い画像を生成
    let redImage = NSImage(size: NSSize(width: 10, height: 10))
    redImage.lockFocus()
    NSColor.red.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: 10, height: 10))
    redImage.unlockFocus()

    let changeCount = rewriter.rewriteImageWithWarning(originalSize: NSSize(width: 100, height: 100))

    #expect(changeCount == pasteboard.changeCount)
    // クリップボードに画像が入っていることを確認
    let types = pasteboard.types ?? []
    #expect(types.contains(.tiff) || types.contains(.png))
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
swift test --filter ClipboardRewriterTests
```

Expected: コンパイルエラー（ClipboardRewriter未定義）

- [ ] **Step 3: ClipboardRewriterを実装**

```swift
// SecureClipboard/ClipboardRewriter.swift
import AppKit

struct ClipboardRewriter {
    /// テキストでクリップボードを上書きし、新しいchangeCountを返す
    @discardableResult
    func rewriteText(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// 警告画像でクリップボードの画像を上書きし、新しいchangeCountを返す
    @discardableResult
    func rewriteImageWithWarning(originalSize: NSSize) -> Int {
        let warningImage = createWarningImage(size: originalSize)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([warningImage])
        return pasteboard.changeCount
    }

    private func createWarningImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // 赤背景
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))

        // 警告テキスト
        let text = "SECRET DETECTED"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: min(size.width, size.height) * 0.1),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        return image
    }
}
```

- [ ] **Step 4: テストを実行して通ることを確認**

```bash
swift test --filter ClipboardRewriterTests
```

Expected: 2テスト PASS

- [ ] **Step 5: コミット**

```bash
git add SecureClipboard/ClipboardRewriter.swift SecureClipboardTests/ClipboardRewriterTests.swift
git commit -m "feat: add ClipboardRewriter for text and image overwrite"
```

---

### Task 4: ImageSecretDetector — Vision OCR + 画像スキャン

**Files:**
- Create: `SecureClipboard/ImageSecretDetector.swift`
- Create: `SecureClipboardTests/ImageSecretDetectorTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// SecureClipboardTests/ImageSecretDetectorTests.swift
import Testing
import AppKit
@testable import SecureClipboard

@Test func extractTextFromImage() async throws {
    // テキストを含む画像を生成
    let image = createImageWithText("AKIAIOSFODNN7EXAMPLE")
    let detector = ImageSecretDetector()
    let extractedText = try await detector.extractText(from: image)
    // OCRが正確でなくても、何らかのテキストが抽出されることを確認
    #expect(extractedText.isEmpty == false)
}

@Test func detectSecretInImage() async throws {
    let image = createImageWithText("aws_access_key_id = AKIAIOSFODNN7EXAMPLE")
    let detector = ImageSecretDetector()
    let result = try await detector.detect(image: image)
    #expect(result.hasSecrets == true)
}

private func createImageWithText(_ text: String) -> NSImage {
    let size = NSSize(width: 400, height: 100)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath.fill(NSRect(origin: .zero, size: size))
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24),
        .foregroundColor: NSColor.black
    ]
    text.draw(at: NSPoint(x: 10, y: 40), withAttributes: attributes)
    image.unlockFocus()
    return image
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
swift test --filter ImageSecretDetectorTests
```

Expected: コンパイルエラー（ImageSecretDetector未定義）

- [ ] **Step 3: ImageSecretDetectorを実装**

```swift
// SecureClipboard/ImageSecretDetector.swift
import AppKit
import Vision

struct ImageDetectionResult {
    let hasSecrets: Bool
    let extractedText: String
}

actor ImageSecretDetector {
    private let scanner: SecretScanner

    init(scanner: SecretScanner? = nil) {
        self.scanner = scanner ?? SecretScanner()
    }

    func extractText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func detect(image: NSImage) async throws -> ImageDetectionResult {
        let text = try await extractText(from: image)
        if text.isEmpty {
            return ImageDetectionResult(hasSecrets: false, extractedText: "")
        }
        let scanResult = try await scanner.scan(text: text)
        return ImageDetectionResult(
            hasSecrets: scanResult.hasSecrets,
            extractedText: text
        )
    }
}
```

- [ ] **Step 4: テストを実行して通ることを確認**

```bash
swift test --filter ImageSecretDetectorTests
```

Expected: 2テスト PASS

- [ ] **Step 5: コミット**

```bash
git add SecureClipboard/ImageSecretDetector.swift SecureClipboardTests/ImageSecretDetectorTests.swift
git commit -m "feat: add ImageSecretDetector with Vision OCR"
```

---

### Task 5: StatusState — アプリ状態管理

**Files:**
- Create: `SecureClipboard/StatusState.swift`

- [ ] **Step 1: StatusStateを実装**

```swift
// SecureClipboard/StatusState.swift
import SwiftUI

struct DetectionRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let summary: String
    let originalText: String?
    let originalImage: NSImage?
}

@Observable
final class StatusState {
    var isEnabled: Bool = true
    var isAlerted: Bool = false
    var recentDetections: [DetectionRecord] = []

    /// 元データの一時保持（最新1件のみ）
    private(set) var lastOriginalText: String?
    private(set) var lastOriginalImage: NSImage?
    private var clearTimer: Timer?

    var iconName: String {
        if !isEnabled { return "lock.shield.fill" }
        return isAlerted ? "exclamationmark.shield.fill" : "lock.shield"
    }

    var iconColor: Color {
        if !isEnabled { return .secondary }
        return isAlerted ? .red : .primary
    }

    func recordDetection(summary: String, originalText: String? = nil, originalImage: NSImage? = nil) {
        let record = DetectionRecord(
            timestamp: Date(),
            summary: summary,
            originalText: originalText,
            originalImage: originalImage
        )
        recentDetections.insert(record, at: 0)
        if recentDetections.count > 5 {
            recentDetections.removeLast()
        }

        lastOriginalText = originalText
        lastOriginalImage = originalImage
        isAlerted = true

        // 30秒後に元データを破棄、5秒後にアラート状態を解除
        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.lastOriginalText = nil
            self?.lastOriginalImage = nil
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.isAlerted = false
        }
    }

    func copyOriginalText() {
        guard let text = lastOriginalText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
```

- [ ] **Step 2: コミット**

```bash
git add SecureClipboard/StatusState.swift
git commit -m "feat: add StatusState for app state management"
```

---

### Task 6: ClipboardMonitor — クリップボード監視

**Files:**
- Create: `SecureClipboard/ClipboardMonitor.swift`
- Create: `SecureClipboardTests/ClipboardMonitorTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// SecureClipboardTests/ClipboardMonitorTests.swift
import Testing
import AppKit
@testable import SecureClipboard

@Test func detectsClipboardChange() async throws {
    let monitor = ClipboardMonitor()
    let pasteboard = NSPasteboard.general

    let initialChangeCount = pasteboard.changeCount

    // クリップボードを変更
    pasteboard.clearContents()
    pasteboard.setString("test", forType: .string)

    let hasChanged = monitor.hasClipboardChanged(since: initialChangeCount)
    #expect(hasChanged == true)
}

@Test func skipsOwnChanges() async throws {
    let monitor = ClipboardMonitor()
    let pasteboard = NSPasteboard.general

    pasteboard.clearContents()
    pasteboard.setString("test", forType: .string)

    // 自分の書き込みとして記録
    monitor.recordOwnChange(changeCount: pasteboard.changeCount)

    let hasChanged = monitor.hasClipboardChanged(since: pasteboard.changeCount - 1)
    // changeCountは変わっているが、自分の変更なのでfalse
    #expect(hasChanged == false)
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
swift test --filter ClipboardMonitorTests
```

Expected: コンパイルエラー

- [ ] **Step 3: ClipboardMonitorを実装**

```swift
// SecureClipboard/ClipboardMonitor.swift
import AppKit
import os

final class ClipboardMonitor {
    private let logger = Logger(subsystem: "com.secretlint.SecureClipboard", category: "ClipboardMonitor")
    private let scanner: SecretScanner
    private let imageDetector: ImageSecretDetector
    private let rewriter: ClipboardRewriter
    private let state: StatusState

    private var lastChangeCount: Int
    private var ownChangeCount: Int?
    private var timer: Timer?

    init(
        scanner: SecretScanner? = nil,
        imageDetector: ImageSecretDetector? = nil,
        rewriter: ClipboardRewriter? = nil,
        state: StatusState? = nil
    ) {
        let scannerInstance = scanner ?? SecretScanner()
        self.scanner = scannerInstance
        self.imageDetector = imageDetector ?? ImageSecretDetector(scanner: scannerInstance)
        self.rewriter = rewriter ?? ClipboardRewriter()
        self.state = state ?? StatusState()
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func hasClipboardChanged(since changeCount: Int) -> Bool {
        let currentChangeCount = NSPasteboard.general.changeCount
        if currentChangeCount == changeCount { return false }
        if let own = ownChangeCount, currentChangeCount == own { return false }
        return true
    }

    func recordOwnChange(changeCount: Int) {
        ownChangeCount = changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() async {
        guard state.isEnabled else { return }
        guard hasClipboardChanged(since: lastChangeCount) else { return }

        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount

        // テキストチェック
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            await scanText(text)
            return
        }

        // 画像チェック
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            await scanImage(image)
        }
    }

    private func scanText(_ text: String) async {
        do {
            let result = try await scanner.scan(text: text)
            if result.hasSecrets {
                logger.info("Secret detected in clipboard text")
                let newChangeCount = rewriter.rewriteText(result.maskedText)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: "テキスト内のシークレットをマスクしました",
                    originalText: result.originalText
                )
                sendNotification(title: "SecureClipboard", body: "クリップボードのシークレットをマスクしました")
            }
        } catch {
            logger.error("Secret scan failed: \(error)")
        }
    }

    private func scanImage(_ image: NSImage) async {
        do {
            let result = try await imageDetector.detect(image: image)
            if result.hasSecrets {
                logger.info("Secret detected in clipboard image via OCR")
                let newChangeCount = rewriter.rewriteImageWithWarning(originalSize: image.size)
                recordOwnChange(changeCount: newChangeCount)
                lastChangeCount = newChangeCount
                state.recordDetection(
                    summary: "画像内のシークレットを検出しました",
                    originalImage: image
                )
                sendNotification(title: "SecureClipboard", body: "クリップボードの画像にシークレットが含まれています")
            }
        } catch {
            logger.error("Image secret detection failed: \(error)")
        }
    }

    private func sendNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}
```

- [ ] **Step 4: テストを実行して通ることを確認**

```bash
swift test --filter ClipboardMonitorTests
```

Expected: 2テスト PASS

- [ ] **Step 5: コミット**

```bash
git add SecureClipboard/ClipboardMonitor.swift SecureClipboardTests/ClipboardMonitorTests.swift
git commit -m "feat: add ClipboardMonitor with polling and auto-scan"
```

---

### Task 7: MenuBarView — メニューバーUI

**Files:**
- Create: `SecureClipboard/MenuBarView.swift`
- Modify: `SecureClipboard/SecureClipboardApp.swift`

- [ ] **Step 1: MenuBarViewを実装**

```swift
// SecureClipboard/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let state: StatusState
    let onQuit: () -> Void

    var body: some View {
        Toggle("有効", isOn: Bindable(state).isEnabled)
        Divider()

        if let _ = state.lastOriginalText {
            Button("元のテキストをコピー") {
                state.copyOriginalText()
            }
            Divider()
        }

        if state.recentDetections.isEmpty {
            Text("検出履歴なし")
                .foregroundStyle(.secondary)
        } else {
            Text("直近の検出:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(state.recentDetections.prefix(5)) { record in
                Text("\(record.timestamp.formatted(.dateTime.hour().minute())) — \(record.summary)")
                    .font(.caption)
            }
        }

        Divider()
        Button("終了") {
            onQuit()
        }
        .keyboardShortcut("q")
    }
}
```

- [ ] **Step 2: SecureClipboardApp.swiftを更新**

```swift
// SecureClipboard/SecureClipboardApp.swift
import SwiftUI

@main
struct SecureClipboardApp: App {
    @State private var state = StatusState()
    @State private var monitor: ClipboardMonitor?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state) {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: state.iconName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(state.isAlerted ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: state.isEnabled) { _, newValue in
            if newValue {
                monitor?.start()
            } else {
                monitor?.stop()
            }
        }
        .onAppear {
            let m = ClipboardMonitor(state: state)
            monitor = m
            m.start()
        }
    }
}
```

- [ ] **Step 3: ビルドして動作確認**

```bash
swift build
# アプリを起動してメニューバーにアイコンが表示されることを確認
swift run
```

- [ ] **Step 4: コミット**

```bash
git add SecureClipboard/MenuBarView.swift SecureClipboard/SecureClipboardApp.swift
git commit -m "feat: add MenuBarView and wire up app entry point"
```

---

### Task 8: 統合テストと動作確認

**Files:**
- Create: `SecureClipboardTests/IntegrationTests.swift`

- [ ] **Step 1: 統合テストを書く**

```swift
// SecureClipboardTests/IntegrationTests.swift
import Testing
import AppKit
@testable import SecureClipboard

@Test func endToEndTextMasking() async throws {
    let state = StatusState()
    let scanner = SecretScanner()
    let rewriter = ClipboardRewriter()
    let monitor = ClipboardMonitor(scanner: scanner, rewriter: rewriter, state: state)

    // AWSキーをクリップボードにコピー
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("aws_access_key_id = AKIAIOSFODNN7EXAMPLE", forType: .string)

    // スキャン実行（手動呼び出し）
    let text = pasteboard.string(forType: .string)!
    let result = try await scanner.scan(text: text)

    #expect(result.hasSecrets == true)
    #expect(result.maskedText.contains("AKIAIOSFODNN7EXAMPLE") == false)
}

@Test func noFalsePositiveOnNormalText() async throws {
    let scanner = SecretScanner()
    let result = try await scanner.scan(text: "Hello, this is a normal message with no secrets.")
    #expect(result.hasSecrets == false)
    #expect(result.maskedText == "Hello, this is a normal message with no secrets.")
}
```

- [ ] **Step 2: 全テストを実行**

```bash
swift test
```

Expected: 全テスト PASS

- [ ] **Step 3: アプリをビルド・起動して手動テスト**

```bash
swift build
swift run &
```

手動テスト:
1. テキストエディタで `AKIAIOSFODNN7EXAMPLE` をコピー → クリップボードがマスクされる
2. 通常のテキストをコピー → 何も起きない
3. メニューバーアイコンが検出時に赤くなる
4. メニューから「元のテキストをコピー」が使える

- [ ] **Step 4: コミット**

```bash
git add SecureClipboardTests/IntegrationTests.swift
git commit -m "test: add integration tests for end-to-end masking"
```

---

### Task 9: .gitignore と README

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: .gitignoreを作成**

```gitignore
# .gitignore
.DS_Store
.build/
*.xcodeproj/xcuserdata/
DerivedData/
.swiftpm/
SecureClipboard/Resources/secretlint
```

- [ ] **Step 2: READMEを作成**

```markdown
# SecureClipboard

macOSメニューバー常駐アプリ。クリップボードにコピーされたテキスト・画像を[secretlint](https://github.com/secretlint/secretlint)で自動スキャンし、シークレットが含まれていればマスクする。

## セットアップ

```bash
# secretlintバイナリをダウンロード
bash scripts/download-secretlint.sh <version>

# ビルド
swift build

# 実行
swift run
```

## 仕組み

1. クリップボードの変更をポーリングで監視（500ms間隔）
2. テキスト: secretlintでスキャンし、シークレット検出時にマスク済みテキストで上書き
3. 画像: Vision frameworkでOCR → secretlintでスキャン → 検出時に警告画像で上書き
4. メニューバーアイコンが赤くなり、macOS通知で知らせる

## License

MIT
```

- [ ] **Step 3: コミット**

```bash
git add .gitignore README.md
git commit -m "docs: add README and .gitignore"
```
