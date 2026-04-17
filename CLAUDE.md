# SecureClipboard

## Build

- Build: `swift build --disable-sandbox` (NSPasteboard access requires sandbox disabled)
- Test: `swift test --disable-sandbox`
- Build .app: `bash scripts/build-app.sh`

## Project Structure

- Swift Package Manager project (Package.swift)
- macOS 14+ menu bar app using SwiftUI MenuBarExtra
- secretlint binary bundled in Resources/ (not checked into git)
- Localization: en (default), ja

## Conventions

- Use `Bundle.module` for accessing resources and localized strings
- Use `String(localized:bundle:)` for localized strings in code
- secretlint binary path resolved via `Bundle.module.url(forResource:)`
- All UI strings defined in `Resources/{lang}.lproj/Localizable.strings`
