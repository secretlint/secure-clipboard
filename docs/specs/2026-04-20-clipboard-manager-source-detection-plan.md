# Clipboard Manager Source Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `skipScanAppIdentifiers` so its values are matched against pasteboard types and `org.nspasteboard.source` in addition to the frontmost bundle identifier, allowing Alfred clipboard-history re-copies to be skipped via `com.runningwithcrayons.alfred.clipping`.

**Architecture:** Add a new `AppConfig.shouldSkipScan(frontmostBundleId:pasteboardTypes:nspasteboardSource:)` that checks the user's skip list against three pasteboard-derived identifiers. `ClipboardMonitor` collects all three identifiers on each change and delegates the decision. Existing `shouldSkipScan(bundleId:)` stays for backward compatibility of existing tests.

**Tech Stack:** Swift 5.10 / Swift Testing, AppKit (`NSPasteboard`, `NSWorkspace`), Swift Package Manager.

---

## File Structure

| File | Role |
|---|---|
| `SecureClipboard/AppConfig.swift` | Add new `shouldSkipScan(frontmostBundleId:pasteboardTypes:nspasteboardSource:)`. Keep existing overload. |
| `SecureClipboard/ClipboardMonitor.swift` | Replace scan-skip check with new API. Demote debug log that was added during investigation. |
| `SecureClipboardTests/AppConfigTests.swift` | Add tests for the new overload. |
| `README.md` | Update `skipScanAppIdentifiers` explanation and the example config JSON. |

---

## Task 1: Add new `shouldSkipScan` overload to `AppConfig` (TDD)

**Files:**
- Modify: `SecureClipboard/AppConfig.swift`
- Modify: `SecureClipboardTests/AppConfigTests.swift`

- [ ] **Step 1.1: Write failing tests**

Append to `SecureClipboardTests/AppConfigTests.swift`:

```swift
@Test func shouldSkipScanMatchesFrontmost() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.1password.1password"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.1password.1password",
        pasteboardTypes: [],
        nspasteboardSource: nil
    ) == true)
}

@Test func shouldSkipScanMatchesPasteboardType() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.runningwithcrayons.alfred.clipping"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Terminal",
        pasteboardTypes: ["public.utf8-plain-text", "com.runningwithcrayons.alfred.clipping"],
        nspasteboardSource: nil
    ) == true)
}

@Test func shouldSkipScanMatchesNspasteboardSource() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.example.SourceApp"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Safari",
        pasteboardTypes: [],
        nspasteboardSource: "com.example.SourceApp"
    ) == true)
}

@Test func shouldSkipScanNoMatchReturnsFalse() {
    let config = AppConfig(
        rules: [],
        patterns: nil,
        skipScanAppIdentifiers: ["com.1password.1password"]
    )
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Safari",
        pasteboardTypes: ["public.utf8-plain-text"],
        nspasteboardSource: nil
    ) == false)
}

@Test func shouldSkipScanNilIdentifiersReturnsFalse() {
    let config = AppConfig(rules: [], patterns: nil, skipScanAppIdentifiers: nil)
    #expect(config.shouldSkipScan(
        frontmostBundleId: "com.apple.Safari",
        pasteboardTypes: ["public.utf8-plain-text"],
        nspasteboardSource: "com.example.App"
    ) == false)
}
```

- [ ] **Step 1.2: Run tests to verify failure**

Run: `swift test --disable-sandbox --filter shouldSkipScanMatchesFrontmost`
Expected: compilation error — `shouldSkipScan(frontmostBundleId:pasteboardTypes:nspasteboardSource:)` is not defined on `AppConfig`.

- [ ] **Step 1.3: Add the new overload**

In `SecureClipboard/AppConfig.swift`, after the existing `shouldSkipScan(bundleId:)` (around line 93-96), add:

```swift
    func shouldSkipScan(
        frontmostBundleId: String?,
        pasteboardTypes: [String],
        nspasteboardSource: String?
    ) -> Bool {
        guard let ids = skipScanAppIdentifiers else { return false }
        if let id = frontmostBundleId, ids.contains(id) { return true }
        if let source = nspasteboardSource, ids.contains(source) { return true }
        return pasteboardTypes.contains(where: { ids.contains($0) })
    }
```

- [ ] **Step 1.4: Run all tests to verify they pass**

Run: `swift test --disable-sandbox`
Expected: all existing tests still pass, and the five new `shouldSkipScan*` tests pass.

- [ ] **Step 1.5: Commit**

```bash
git add SecureClipboard/AppConfig.swift SecureClipboardTests/AppConfigTests.swift
git commit -m "$(cat <<'EOF'
feat: match skipScanAppIdentifiers against pasteboard types and nspasteboard.source

Add AppConfig.shouldSkipScan(frontmostBundleId:pasteboardTypes:nspasteboardSource:)
that checks the configured identifiers against the frontmost bundle ID,
pasteboard type strings, and the org.nspasteboard.source value. Enables
skipping re-copies from clipboard managers (e.g. Alfred's
com.runningwithcrayons.alfred.clipping pasteboard type) without a new config key.
EOF
)"
```

---

## Task 2: Wire `ClipboardMonitor` to the new overload and demote debug log

**Files:**
- Modify: `SecureClipboard/ClipboardMonitor.swift`

- [ ] **Step 2.1: Replace the investigation block with the new call**

In `SecureClipboard/ClipboardMonitor.swift`, find the block inside the `Thread.detachNewThread` closure that currently reads (around lines 50-62):

```swift
                if current != self.lastChangeCount, self.ownChangeCount != current {
                    self.lastChangeCount = current

                    // Capture source app at the moment of clipboard change
                    let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
                    let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

                    // [DEBUG] Log pasteboard metadata to investigate nspasteboard.org conventions
                    let types = pasteboard.types ?? []
                    let typeList = types.map { $0.rawValue }.joined(separator: ", ")
                    let nsSource = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
                    let hasTransient = types.contains { $0.rawValue == "org.nspasteboard.TransientType" }
                    let hasAutoGenerated = types.contains { $0.rawValue == "org.nspasteboard.AutoGeneratedType" }
                    let hasConcealed = types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" }
                    self.logger.info("Clipboard changed. frontmost=\(sourceBundleId ?? "nil", privacy: .public), nspasteboard.source=\(nsSource ?? "nil", privacy: .public), transient=\(hasTransient, privacy: .public), autoGenerated=\(hasAutoGenerated, privacy: .public), concealed=\(hasConcealed, privacy: .public), types=[\(typeList, privacy: .public)]")

                    // Check if source app should be ignored
                    let config = AppConfig.load()
                    if config.shouldSkipScan(bundleId: sourceBundleId) {
```

Replace it with:

```swift
                if current != self.lastChangeCount, self.ownChangeCount != current {
                    self.lastChangeCount = current

                    // Capture source app at the moment of clipboard change
                    let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
                    let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

                    let pasteboardTypes = (pasteboard.types ?? []).map { $0.rawValue }
                    let nspasteboardSource = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))

                    self.logger.debug("Clipboard changed. frontmost=\(sourceBundleId ?? "nil", privacy: .public), nspasteboard.source=\(nspasteboardSource ?? "nil", privacy: .public), types=[\(pasteboardTypes.joined(separator: ", "), privacy: .public)]")

                    // Check if the copy source should be ignored
                    let config = AppConfig.load()
                    if config.shouldSkipScan(
                        frontmostBundleId: sourceBundleId,
                        pasteboardTypes: pasteboardTypes,
                        nspasteboardSource: nspasteboardSource
                    ) {
```

The closing `{` on the `if config.shouldSkipScan(...)` line keeps the existing body (`Thread.sleep(forTimeInterval: 0.5); continue`). Do not touch the rest of the loop.

- [ ] **Step 2.2: Build and run tests**

Run: `swift build --disable-sandbox`
Expected: `Build complete!` with no new errors. Deprecation warnings for `NSUserNotification*` are pre-existing and fine.

Run: `swift test --disable-sandbox`
Expected: all tests pass.

- [ ] **Step 2.3: Commit**

```bash
git add SecureClipboard/ClipboardMonitor.swift
git commit -m "$(cat <<'EOF'
refactor: route ClipboardMonitor skip check through new matcher

Collect pasteboard types and org.nspasteboard.source alongside the
frontmost bundle identifier, then delegate the skip decision to the
new AppConfig.shouldSkipScan overload. The diagnostic log is now
logged at .debug level.
EOF
)"
```

---

## Task 3: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 3.1: Update the example config JSON**

In `README.md`, replace the line currently at line 76:

```json
    "skipScanAppIdentifiers": ["com.1password.1password"],
```

with:

```json
    "skipScanAppIdentifiers": [
        "com.1password.1password",
        "com.runningwithcrayons.Alfred",
        "com.runningwithcrayons.alfred.clipping"
    ],
```

- [ ] **Step 3.2: Update the `skipScanAppIdentifiers` section**

In `README.md`, replace the paragraph currently at lines 106-110:

```markdown
### skipScanAppIdentifiers

Bundle identifiers of apps to skip scanning for. Clipboard changes from these apps are not scanned. Useful for password managers like 1Password.

Config changes are picked up on the next clipboard copy — no restart required.
```

with:

```markdown
### skipScanAppIdentifiers

Identifiers to skip scanning for. Each value is matched against:

1. The frontmost app's bundle identifier at the moment of copy
2. The `org.nspasteboard.source` string on the pasteboard, if present
3. Any pasteboard type string on the clipboard

Use the frontmost bundle ID for apps like 1Password where the app is active when copying (`com.1password.1password`).

Clipboard managers such as Alfred write a distinctive pasteboard type when re-copying from their history. To ignore re-copies from Alfred's clipboard history, add `com.runningwithcrayons.alfred.clipping` (the pasteboard type) — optionally together with `com.runningwithcrayons.Alfred` (the bundle ID) for the case when Alfred itself is still frontmost.

Config changes are picked up on the next clipboard copy — no restart required.
```

- [ ] **Step 3.3: Commit**

```bash
git add README.md
git commit -m "docs: document pasteboard-type matching in skipScanAppIdentifiers"
```

---

## Task 4: Manual verification

This step cannot be automated — it requires a real Alfred installation and an interactive desktop session.

- [ ] **Step 4.1: Build the .app**

Run: `bash scripts/build-app.sh`
Expected: `Built: .build/SecureClipboard.app`.

- [ ] **Step 4.2: Stop any existing SecureClipboard process and launch the new build**

Run:
```bash
pkill -x SecureClipboard || true
open .build/SecureClipboard.app
```

- [ ] **Step 4.3: Edit the local config**

Open `~/.config/secure-clipboard/config.json` and make sure `skipScanAppIdentifiers` contains at least `com.runningwithcrayons.alfred.clipping`. (No restart needed — config is re-read on each scan.)

- [ ] **Step 4.4: Verify Alfred history re-copy is ignored**

1. Copy a known secret (e.g. `AKIAIOSFODNN7EXAMPLE`) from a normal app → SecureClipboard masks it as expected.
2. Open Alfred's clipboard history (⌥⌘C by default) and re-copy the masked entry — or any entry from history.
3. Expected: no new entry appears in SecureClipboard's detection history; no mask is applied.
4. Optional: `log stream --predicate 'subsystem == "com.secretlint.SecureClipboard"' --level debug --style compact` should show a line including `types=[..., com.runningwithcrayons.alfred.clipping]`.

- [ ] **Step 4.5: Verify normal copy still scans**

1. Copy a fresh secret from a regular app (Terminal, Safari, etc.).
2. Expected: SecureClipboard detects and masks as before.

- [ ] **Step 4.6: Clean up**

1. Quit the test build.
2. Restart your regular SecureClipboard.app if needed.

---

## Self-Review

Skimmed against spec `docs/specs/2026-04-20-clipboard-manager-source-detection-design.md`:

- Spec coverage:
  - 「`skipScanAppIdentifiers` の意味を拡張」→ Task 1 の新 overload
  - 「`ClipboardMonitor` 側ではこの関数を呼び」→ Task 2
  - 「ログレベルを `.debug` に」→ Task 2.1
  - 「既存 `shouldSkipScan(bundleId:)` は残す」→ Task 1 では既存を削除しない（既存テストが維持される）
  - 「READMEに設定例追加」→ Task 3
  - 「manual 確認手順」→ Task 4
  - 「sourceApp 表示は変更しない」→ どのタスクでも `sourceApp` のロジックには触れていない ✅
  - 「新 config キーを追加しない」→ `AppConfig` の公開プロパティは変更しない ✅
- Placeholder scan: no TBD/TODO; all code blocks are literal and complete.
- Type consistency: the method signature `shouldSkipScan(frontmostBundleId:pasteboardTypes:nspasteboardSource:)` is identical in Task 1's tests, Task 1's implementation, and Task 2's call site.
- Ambiguity: ClipboardMonitor replacement block shows the exact existing code and the exact new code.
