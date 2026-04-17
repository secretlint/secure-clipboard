# SecureClipboard

macOS menu bar app that automatically scans clipboard content with [secretlint](https://github.com/secretlint/secretlint) and masks detected secrets. Secure by default.

## Install

```bash
curl -fSL https://github.com/secretlint/secure-clipboard/releases/latest/download/SecureClipboard.app.zip -o /tmp/SecureClipboard.app.zip
unzip -o /tmp/SecureClipboard.app.zip -d /Applications
xattr -cr /Applications/SecureClipboard.app
open /Applications/SecureClipboard.app
```

## Features

- Monitors clipboard changes (500ms polling)
- Text: scans with secretlint, replaces secrets with `***`
- Image: OCR via Vision framework, scans extracted text, replaces with warning image
- Menu bar icon turns red on detection with macOS notification
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

Supported secret types: AWS, GitHub, Slack, GCP, Azure, npm, Docker, and [many more](https://github.com/secretlint/secretlint#rules).

## Configuration

SecureClipboard uses secretlint for scanning. You can customize rules via the menu: "Open .secretlintrc.json".

Config file location: `~/.config/secure-clipboard/.secretlintrc.json`

Default config includes `@secretlint/secretlint-rule-preset-recommend` and `@secretlint/secretlint-rule-pattern`. See [secretlint rules](https://github.com/secretlint/secretlint#rules) for available rules.

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
├── ClipboardMonitor.swift       # NSPasteboard polling, change detection
├── SecretScanner.swift          # secretlint binary subprocess
├── ClipboardRewriter.swift      # Clipboard overwrite (text + image)
├── ImageSecretDetector.swift    # Vision OCR + secret scan
├── StatusState.swift            # Observable app state
├── MenuBarView.swift            # Menu bar UI
├── SecretlintUpdater.swift      # Auto-update from GitHub releases
└── Resources/
    ├── secretlintrc.json        # Default secretlint config
    ├── en.lproj/                # English strings
    └── ja.lproj/                # Japanese strings
```

## License

MIT
