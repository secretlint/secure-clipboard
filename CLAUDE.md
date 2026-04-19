# SecureClipboard

## Build

- Build: `swift build --disable-sandbox` (NSPasteboard access requires sandbox disabled)
- Test: `swift test --disable-sandbox`
- Build .app: `bash scripts/build-app.sh`

## Release

- Bump version: `bash scripts/bump-version.sh <version>`
  - Updates `SecureClipboard/AppVersion.swift` and `scripts/build-app.sh`
- Tag and push: `git tag v<version> && git push --tags`
- GitHub Actions release workflow builds .app.zip and attaches to release

## Project Structure

- Swift Package Manager project (Package.swift)
- macOS 14+ menu bar app using SwiftUI MenuBarExtra
- secretlint binary bundled in Resources/ (not checked into git)
- Localization: en (default), ja
- App version defined in `SecureClipboard/AppVersion.swift`

## Architecture

- `AppState` (singleton) holds `StatusState` and `ClipboardMonitor`, ensuring they outlive SwiftUI struct lifecycle
- `ClipboardMonitor` uses `Thread.detachNewThread` for polling — `Timer` and `DispatchSource` don't fire reliably from SwiftUI App `init()`
- `SecretScanner` calls secretlint binary via `Process` subprocess with `--format=mask-result` and `--secretlintrc` (config written to temp file to avoid macOS NFD normalization of Process arguments)
- `ImageSecretDetector` uses Vision OCR to extract text + bounding boxes, then `SecretScanner` checks for secrets
- `ClipboardRewriter` redacts image secrets using CICrystallize + CIGaussianBlur with background color fill
- `SecretlintUpdater` checks GitHub API for new releases on app launch

## Key Design Decisions

- SPM `.copy("Resources")` is used (not `.process()`) — `.process()` changes bundle structure and breaks `Bundle.module` path resolution
- `.app` bundle must have resource bundle at both `AppName.app/` root AND `Contents/MacOS/` for `Bundle.module` to find it
- `NSUserNotification` is used instead of `UNUserNotificationCenter` — UNUserNotificationCenter crashes without Bundle Identifier in SPM builds
- Clipboard self-write detection uses `changeCount` tracking to avoid re-scanning own writes
- Config file is re-read on every scan (no caching) so changes take effect without restart
- "Copy Original Text" auto-clears clipboard after 90 seconds (matching 1Password behavior)
- CLI tools (`secure-pbcopy`/`secure-pbpaste`) resolve symlinks via `readlink` loop to find secretlint binary in the .app bundle

## Testing

- `NSPasteboard.general` はプロセス内で共有されるため、ペーストボードに書き込むテストは `@Suite(.serialized)` でラップして直列実行にする
- ペーストボードを使わないテスト（状態管理、アイコン名など）は並列実行のままでよい

## Conventions

- Use `Bundle.module` for accessing resources and localized strings
- Use `String(localized:bundle:)` for localized strings in code
- secretlint binary path resolved via `Bundle.module.url(forResource:withExtension:subdirectory:)`
- All UI strings defined in `Resources/{lang}.lproj/Localizable.strings`
- User config: `~/.config/secure-clipboard/config.json`
- Bundled secretlint rules: `preset-recommend` and `pattern` (pattern is dynamically added when mask patterns are configured)
- Custom patterns with `action: "mask"` are passed to secretlint as `rule-pattern` options
- Custom patterns with `action: "discard"` trigger full clipboard discard (detected via `--format=json` name matching)
