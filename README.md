# SecureClipboard

macOS menu bar app that automatically scans clipboard content with [secretlint](https://github.com/secretlint/secretlint) and masks detected secrets. Secure by default.

## Motivation

Secrets copied to the clipboard can accidentally end up in unintended places — a Linear issue title, a Slack message, a search bar. You don't always notice what's in your clipboard before pasting. SecureClipboard masks secrets at the moment of copy, so even accidental pastes are safe.

When you intentionally need the raw value, select "Copy Original Text" from the menu bar to retrieve the unmasked content. The raw value is automatically cleared from the clipboard after 90 seconds (same as 1Password). This two-step process ensures secrets are only exposed when you explicitly choose to, and never linger on the clipboard.

## Install

```bash
curl -fSL https://github.com/secretlint/secure-clipboard/releases/latest/download/SecureClipboard.app.zip -o /tmp/SecureClipboard.app.zip
unzip -o /tmp/SecureClipboard.app.zip -d /Applications
xattr -cr /Applications/SecureClipboard.app
open /Applications/SecureClipboard.app
```

## Uninstall

```bash
rm -rf /Applications/SecureClipboard.app
rm -f /usr/local/bin/secure-pbpaste /usr/local/bin/secure-pbcopy
```

## Features

- Monitors clipboard changes (500ms polling)
- Text: scans with secretlint, replaces secrets with `***`
- Image: OCR via Vision framework, scans extracted text, redacts secret regions with natural-looking crystallize + blur effect
- Menu bar icon turns red on detection with macOS notification
- "Copy Original Text" menu item to retrieve unmasked content (auto-cleared after 90 seconds, same as [1Password](https://support.1password.com/copy-passwords/))
- CLI tools: `secure-pbpaste` and `secure-pbcopy` bundled in the app
- Auto-updates secretlint binary from GitHub releases
- Localized (English / Japanese)

## Demo

Copy text containing a secret — SecureClipboard will automatically replace it with `***` in your clipboard.

Try it: copy the following Slack token and paste it somewhere.

```
xoxb-1234567890123-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx
```

After copying, your clipboard will contain:

```
*********************************************************
```

If you need the raw (unmasked) text, click the menu bar icon and select "Copy Original Text". The clipboard is automatically cleared after 90 seconds.

Supported secret types: AWS, GitHub, Slack, GCP, Azure, npm, Docker, and [more](https://github.com/secretlint/secretlint/tree/master/packages/%40secretlint/secretlint-rule-preset-recommend#rules). You can also define custom patterns.

## Configuration

Config file: `~/.config/secure-clipboard/config.json` (open via menu: "Open config.json")

```json
{
    "rules": [
        { "id": "@secretlint/secretlint-rule-preset-recommend" }
    ],
    "patterns": [
        { "name": "mask-example", "pattern": "/INTERNAL_\\w+/i", "action": "mask" },
        { "name": "discard-example", "pattern": "/CONFIDENTIAL/i", "action": "discard" }
    ],
    "skipScanAppIdentifiers": ["com.1password.1password"]
}
```

### rules

secretlint rules for detecting known secrets. `@secretlint/secretlint-rule-preset-recommend` detects AWS, GitHub, Slack, GCP, Azure, npm, Docker, and [more](https://github.com/secretlint/secretlint/tree/master/packages/%40secretlint/secretlint-rule-preset-recommend#rules). Removing this rule disables all built-in secret detection.

### patterns

Custom patterns with two actions:

| | Text | Image |
|---|---|---|
| `"action": "mask"` | Matched portions replaced with `***` | Secret regions redacted with crystallize + blur effect |
| `"action": "discard"` | Entire clipboard replaced with `[DISCARDED: <name>]` | Entire image replaced with red warning image |

Patterns use `/regex/flags` syntax. Supported flags: `i` (case-insensitive), `m` (multiline), `s` (dotAll).

### skipScanAppIdentifiers

Bundle identifiers of apps to skip scanning for. Clipboard changes from these apps are not scanned. Useful for password managers like 1Password.

Config changes are picked up on the next clipboard copy — no restart required.

## CLI Tools

SecureClipboard bundles `secure-pbpaste` and `secure-pbcopy` — drop-in replacements for `pbpaste` and `pbcopy` that automatically mask secrets.

Unlike regular `pbcopy`, raw text never touches the clipboard. `secure-pbcopy` sends text to the running app via IPC (Unix Domain Socket), the app scans and masks it, and only the masked text is written to the clipboard. If the app is not running, it is automatically launched in the background.

Install via menu bar: click the SecureClipboard icon → "Install CLI Tools". This creates symlinks in `/usr/local/bin/` (requires admin password).

Or manually:

```bash
ln -sf /Applications/SecureClipboard.app/Contents/MacOS/secure-pbpaste /usr/local/bin/secure-pbpaste
ln -sf /Applications/SecureClipboard.app/Contents/MacOS/secure-pbcopy /usr/local/bin/secure-pbcopy
```

Usage:

```bash
secure-pbpaste              # outputs clipboard text with secrets masked
echo "text" | secure-pbcopy # copies text to clipboard with secrets masked
```

## Development

```bash
# Download secretlint binary
bash scripts/download-secretlint.sh 11.7.1

# Build
swift build --disable-sandbox

# Test
swift test --disable-sandbox

# Build .app bundle
bash scripts/build-app.sh
```

`--disable-sandbox` is required for NSPasteboard access.

## Architecture

```
SecureClipboard/
├── SecureClipboardApp.swift     # App entry, menu bar setup
├── AppConfig.swift              # Config loading (config.json)
├── ClipboardMonitor.swift       # NSPasteboard polling, change detection
├── SecretScanner.swift          # secretlint binary subprocess
├── ClipboardRewriter.swift      # Clipboard overwrite (text + image)
├── ImageSecretDetector.swift    # Vision OCR + secret scan
├── IPCServer.swift              # Unix Domain Socket server for CLI tools
├── StatusState.swift            # Observable app state
├── MenuBarView.swift            # Menu bar UI
├── SecretlintUpdater.swift      # Auto-update from GitHub releases
└── Resources/
    ├── secretlintrc.json        # Default secretlint config
    ├── en.lproj/                # English strings
    └── ja.lproj/                # Japanese strings
SecureClipboardCLI/
└── SecurePBMain.swift           # secure-pbpaste/secure-pbcopy binary
```

## License

MIT
