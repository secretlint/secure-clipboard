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

## Conventions

- Use `Bundle.module` for accessing resources and localized strings
- Use `String(localized:bundle:)` for localized strings in code
- secretlint binary path resolved via `Bundle.module.url(forResource:)`
- All UI strings defined in `Resources/{lang}.lproj/Localizable.strings`
- User config: `~/.config/secure-clipboard/.secretlintrc.json`
