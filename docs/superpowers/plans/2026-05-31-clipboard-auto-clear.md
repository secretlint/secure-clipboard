# クリップボード自動クリア機能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 最後のクリップボード変更からN秒経過したら自動でクリップボードをクリアする設定オプション (`clearClipboardAfterSeconds`) を追加する。

**Architecture:** `AppConfig` に optional な `clearClipboardAfterSeconds` を追加し、`ClipboardMonitor` のポーリングループで変更検出時に「N秒後クリア」を予約する。クリア発火時は予約時に捕捉した `changeCount` と現在値が一致するときだけ `clearContents()` を実行する（changeCount ガード方式、`copyOriginalText` と同じイディオム）。クリア書き込みは `recordOwnChange` で自己書き込みとして記録し、無限クリアループを防ぐ。

**Tech Stack:** Swift / Swift Package Manager / swift-testing (`import Testing`) / AppKit (`NSPasteboard`)

**Build/Test commands:** `swift build --disable-sandbox` / `swift test --disable-sandbox`

---

## File Structure

- `SecureClipboard/AppConfig.swift` — `clearClipboardAfterSeconds: Double?` フィールド追加、`default` に反映。
- `SecureClipboard/ClipboardMonitor.swift` — クリア予約・実行ロジック追加、ポーリングループに呼び出し追加。
- `SecureClipboardTests/AppConfigTests.swift` — 新フィールドのデコード/デフォルトのテスト追加。
- `SecureClipboardTests/ClipboardMonitorTests.swift` — クリア実行ロジック (`performClipboardClearIfUnchanged`) のテスト追加。
- `SecureClipboard/MenuBarView.swift` — `defaultConfig` テンプレートに新キー追記。
- `README.md` — config 例と新セクション追記。

---

## Task 1: AppConfig に clearClipboardAfterSeconds を追加

**Files:**
- Modify: `SecureClipboard/AppConfig.swift`
- Test: `SecureClipboardTests/AppConfigTests.swift`

`AppConfig` は memberwise initializer と Codable を合成で利用している。optional プロパティは memberwise init で省略可能（既存の `scanDelaySeconds` と同じ）。Codable は欠落キーを `nil` にデコードする。

- [ ] **Step 1: Write the failing tests**

`SecureClipboardTests/AppConfigTests.swift` の末尾（最後の `}` の前ではなくファイル末尾、トップレベル `@Test` 関数群と同じ並び）に追加:

```swift
@Test func clearClipboardAfterSecondsDefaultIsNil() {
    let config = AppConfig.default
    #expect(config.clearClipboardAfterSeconds == nil)
}

@Test func clearClipboardAfterSecondsParsesFromJSON() throws {
    let json = """
    {"rules":[],"clearClipboardAfterSeconds":60}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.clearClipboardAfterSeconds == 60)
}

@Test func clearClipboardAfterSecondsOptionalInJSON() throws {
    let json = """
    {"rules":[]}
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.clearClipboardAfterSeconds == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --disable-sandbox --filter clearClipboardAfterSeconds`
Expected: コンパイルエラー（`clearClipboardAfterSeconds` is not a member of `AppConfig`）。

- [ ] **Step 3: Add the field to AppConfig**

`SecureClipboard/AppConfig.swift` のプロパティ宣言（`var scanDelaySeconds: Double?` の直後）に追加:

```swift
    var scanDelaySeconds: Double?
    var clearClipboardAfterSeconds: Double?
```

`AppConfig.default` に明示的に `nil` を渡す（既存の `scanDelaySeconds: nil` の直後に追加）:

```swift
    static let `default` = AppConfig(
        rules: [
            SecretlintRule(id: "@secretlint/secretlint-rule-preset-recommend", options: nil)
        ],
        patterns: nil,
        skipScanAppIdentifiers: nil,
        scanDelaySeconds: nil,
        clearClipboardAfterSeconds: nil
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --disable-sandbox --filter clearClipboardAfterSeconds`
Expected: PASS（3テスト）。

- [ ] **Step 5: Commit**

```bash
git add SecureClipboard/AppConfig.swift SecureClipboardTests/AppConfigTests.swift
git commit -m "feat: add clearClipboardAfterSeconds config option"
```

---

## Task 2: ClipboardMonitor にクリア実行ロジックを追加

**Files:**
- Modify: `SecureClipboard/ClipboardMonitor.swift`
- Test: `SecureClipboardTests/ClipboardMonitorTests.swift`

`performClipboardClearIfUnchanged(capturedChangeCount:)` は同期メソッドで、changeCount ガードと空チェックを行い、クリア時は `recordOwnChange` + `lastChangeCount` を更新する。テスト可能にするため `internal`（デフォルト可視性）にする。

- [ ] **Step 1: Write the failing tests**

`SecureClipboardTests/ClipboardMonitorTests.swift` の `@Suite(.serialized) struct ClipboardMonitorTests {` 内（既存テストの後、閉じ `}` の前）に追加:

```swift
    @Test func clearsWhenChangeCountMatches() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString("stale content", forType: .string)
        let captured = pasteboard.changeCount

        monitor.performClipboardClearIfUnchanged(capturedChangeCount: captured)

        #expect(pasteboard.string(forType: .string) == nil)
        // クリア書き込みは自己書き込みとして記録され、再検出されない
        #expect(monitor.hasClipboardChanged(since: captured) == false)
    }

    @Test func doesNotClearWhenChangeCountStale() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let stale = pasteboard.changeCount

        // captured より後に新しい内容がコピーされた状況を再現
        pasteboard.clearContents()
        pasteboard.setString("new content", forType: .string)

        monitor.performClipboardClearIfUnchanged(capturedChangeCount: stale)

        // 最新の内容は消えない（no-op）
        #expect(pasteboard.string(forType: .string) == "new content")
    }

    @Test func doesNotClearWhenAlreadyEmpty() async throws {
        let monitor = ClipboardMonitor()
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        let captured = pasteboard.changeCount

        monitor.performClipboardClearIfUnchanged(capturedChangeCount: captured)

        // 空のまま no-op（changeCount を無駄に変動させない）
        #expect(pasteboard.changeCount == captured)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --disable-sandbox --filter ClipboardMonitorTests`
Expected: コンパイルエラー（`performClipboardClearIfUnchanged` not found）。

- [ ] **Step 3: Implement the clear methods**

`SecureClipboard/ClipboardMonitor.swift` の `func stop()` の直後（`private func scanText` の前）に追加:

```swift
    /// Clear the clipboard only if it hasn't changed since `capturedChangeCount`
    /// and is not already empty. Records the clear as an own-change so the
    /// monitor does not re-detect it (prevents an infinite clear loop).
    func performClipboardClearIfUnchanged(capturedChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == capturedChangeCount else { return }
        guard pasteboard.types?.isEmpty == false else { return }

        pasteboard.clearContents()
        let newChangeCount = pasteboard.changeCount
        recordOwnChange(changeCount: newChangeCount)
        lastChangeCount = newChangeCount
        logger.info("Clipboard auto-cleared")
    }

    /// Schedule an auto-clear after `seconds`, keyed to the current changeCount.
    private func scheduleClearIfEnabled(_ config: AppConfig) {
        guard let seconds = config.clearClipboardAfterSeconds, seconds > 0 else { return }
        let captured = NSPasteboard.general.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.performClipboardClearIfUnchanged(capturedChangeCount: captured)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --disable-sandbox --filter ClipboardMonitorTests`
Expected: PASS（既存2 + 新規3 = 5テスト）。

注: `scheduleClearIfEnabled` はまだ呼び出されないため "unused" 警告が出る場合がある。Task 3 で呼び出しを追加するので問題ない。

- [ ] **Step 5: Commit**

```bash
git add SecureClipboard/ClipboardMonitor.swift SecureClipboardTests/ClipboardMonitorTests.swift
git commit -m "feat: add clipboard clear logic with changeCount guard"
```

---

## Task 3: ポーリングループからクリアを予約する

**Files:**
- Modify: `SecureClipboard/ClipboardMonitor.swift`

スケジュールは2箇所で呼ぶ。(1) `skipScanAppIdentifiers` で `continue` する前（スキャン除外アプリのコピーも古い内容を残さない対象にするため、`current` の count で予約）。(2) テキスト/画像処理の後（マスク後の最終 count で予約）。設定無効時は `scheduleClearIfEnabled` 内で早期 return するため副作用なし。

このタスクはタイミング依存の非同期挙動のため、変更後は `swift build` でのコンパイル確認と手動検証で担保する（自動テストは Task 2 の同期ロジックでカバー済み）。

- [ ] **Step 1: Add schedule call before the skipScan continue**

`SecureClipboard/ClipboardMonitor.swift` の `start()` 内、skipScan ブロックを次のように変更する。変更前:

```swift
                    if config.shouldSkipScan(
                        frontmostBundleId: sourceBundleId,
                        pasteboardTypes: pasteboardTypes,
                        nspasteboardSource: nspasteboardSource
                    ) {
                        Thread.sleep(forTimeInterval: 0.5)
                        continue
                    }
```

変更後:

```swift
                    if config.shouldSkipScan(
                        frontmostBundleId: sourceBundleId,
                        pasteboardTypes: pasteboardTypes,
                        nspasteboardSource: nspasteboardSource
                    ) {
                        // Scan is skipped, but stale content should still auto-clear.
                        self.scheduleClearIfEnabled(config)
                        Thread.sleep(forTimeInterval: 0.5)
                        continue
                    }
```

- [ ] **Step 2: Add schedule call after text/image processing**

同じ `if current != self.lastChangeCount, self.ownChangeCount != current {` ブロックの末尾、テキスト/画像処理の `} else if ... { ... }` チェーンの直後（このブロックを閉じる `}` の直前）に追加する。変更前の該当箇所:

```swift
                    } else if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                              let image = NSImage(data: imageData) {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.scanImage(image, sourceApp: sourceApp)
                            semaphore.signal()
                        }
                        semaphore.wait()
                    }
                }
                Thread.sleep(forTimeInterval: 0.5)
```

変更後（`}` の前に `scheduleClearIfEnabled` を追加）:

```swift
                    } else if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                              let image = NSImage(data: imageData) {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await self.scanImage(image, sourceApp: sourceApp)
                            semaphore.signal()
                        }
                        semaphore.wait()
                    }

                    // Schedule auto-clear keyed to the post-scan changeCount
                    // (covers external copies and SecureClipboard's own masked writes).
                    self.scheduleClearIfEnabled(config)
                }
                Thread.sleep(forTimeInterval: 0.5)
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build --disable-sandbox`
Expected: ビルド成功、`scheduleClearIfEnabled` の unused 警告が消える。

- [ ] **Step 4: Run full test suite**

Run: `swift test --disable-sandbox`
Expected: 全テスト PASS。

- [ ] **Step 5: Commit**

```bash
git add SecureClipboard/ClipboardMonitor.swift
git commit -m "feat: schedule clipboard auto-clear on clipboard changes"
```

---

## Task 4: ドキュメントとデフォルト設定テンプレートを更新

**Files:**
- Modify: `SecureClipboard/MenuBarView.swift`
- Modify: `README.md`

- [ ] **Step 1: Update the defaultConfig template**

`SecureClipboard/MenuBarView.swift` の `defaultConfig` 文字列を変更する。変更前:

```swift
    private let defaultConfig = """
    {
        "rules": [
            {
                "id": "@secretlint/secretlint-rule-preset-recommend"
            }
        ],
        "patterns": [],
        "skipScanAppIdentifiers": [],
        "scanDelaySeconds": 0
    }
    """
```

変更後（`scanDelaySeconds` の行末にカンマを追加し、新キーを追記）:

```swift
    private let defaultConfig = """
    {
        "rules": [
            {
                "id": "@secretlint/secretlint-rule-preset-recommend"
            }
        ],
        "patterns": [],
        "skipScanAppIdentifiers": [],
        "scanDelaySeconds": 0,
        "clearClipboardAfterSeconds": null
    }
    """
```

- [ ] **Step 2: Update README config example**

`README.md` の最初の config 例（67-82行付近）の `"scanDelaySeconds": 0` を次のように変更する。変更前:

```json
    "scanDelaySeconds": 0
}
```

変更後:

```json
    "scanDelaySeconds": 0,
    "clearClipboardAfterSeconds": null
}
```

- [ ] **Step 3: Add README section for the new option**

`README.md` の `### scanDelaySeconds` セクション（116-124行）の直後、`### skipScanAppIdentifiers` の前に新セクションを追加する:

```markdown
### clearClipboardAfterSeconds

Seconds after the last clipboard change before the clipboard is automatically cleared. Default: `null` (disabled). This helps avoid accidentally pasting stale content copied earlier. The timer effectively resets on every clipboard change: if you copy something new within the interval, only the latest content is cleared. Set to `null` or `0` to disable.

```json
{
    "clearClipboardAfterSeconds": 60
}
```
```

- [ ] **Step 4: Build to verify nothing broke**

Run: `swift build --disable-sandbox`
Expected: ビルド成功。

- [ ] **Step 5: Commit**

```bash
git add SecureClipboard/MenuBarView.swift README.md
git commit -m "docs: document clearClipboardAfterSeconds option"
```

---

## Manual Verification (実装完了後)

`.app` をビルドして実機確認する: `bash scripts/build-app.sh`

設定 `~/.config/secure-clipboard/config.json` に `"clearClipboardAfterSeconds": 10` を入れて以下を確認:

1. **基本クリア**: 何かをコピー → 10秒後にクリップボードが空になる（`pbpaste` が空）。
2. **タイマーリセット**: コピー → 5秒後に別の内容をコピー → 最初の内容は途中で消えず、最新の内容が（その10秒後に）クリアされる。
3. **ループ防止（最重要）**: 機能ON・何もコピーせず放置 → 無限クリアループが起きず、Console.app のログに `Clipboard auto-cleared` が繰り返し出力されない。
4. **無効時**: `null` または未設定 → 自動クリアが一切発生しない。

---

## Self-Review

- **Spec coverage**:
  - config仕様（`clearClipboardAfterSeconds: Double?`, default nil, 0/負値/null は無効）→ Task 1 + `scheduleClearIfEnabled` の `seconds > 0` ガード。
  - スケジュール位置（skipScan continue 前 + マスク後の最終 count）→ Task 3 の2箇所の呼び出し。
  - 自己クリアループ防止（recordOwnChange + 空 no-op）→ Task 2 の `performClipboardClearIfUnchanged`。
  - マスク済み内容の扱い（post-mask count をキー）→ Task 3 Step 2。
  - copyOriginalText 据え置き → 本プランでは `StatusState` を変更しないため自動的に維持。
  - 検証3項目 → Manual Verification に反映。
- **Placeholder scan**: プレースホルダなし。全ステップに実コードを記載。
- **Type consistency**: `performClipboardClearIfUnchanged(capturedChangeCount:)`, `scheduleClearIfEnabled(_:)`, `clearClipboardAfterSeconds` の名称・シグネチャは Task 1〜3 で一貫。`recordOwnChange(changeCount:)` / `lastChangeCount` / `logger` は既存 ClipboardMonitor のメンバ。
