# SecureClipboard

macOS menu bar app that automatically scans clipboard content with [secretlint](https://github.com/secretlint/secretlint) and masks detected secrets. Secure by default.

## Features

- Monitors clipboard changes (500ms polling)
- Text: scans with secretlint, replaces secrets with `***`
- Image: OCR via Vision framework, scans extracted text, replaces with warning image
- Menu bar icon turns red on detection with macOS notification
- Auto-updates secretlint binary from GitHub releases
- Localized (English / Japanese)

## Install

```bash
# Download secretlint binary
bash scripts/download-secretlint.sh 11.7.1

# Build .app bundle
bash scripts/build-app.sh

# Launch
open .build/SecureClipboard.app
```

## Development

```bash
# Build
swift build --disable-sandbox

# Test
swift test --disable-sandbox

# Run (debug)
.build/debug/SecureClipboard
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
