# SecureClipboard

macOS menu bar app that automatically scans clipboard content with [secretlint](https://github.com/secretlint/secretlint) and masks detected secrets. Secure by default.

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
- "Copy Original Text" menu item to retrieve unmasked content (available for 30 seconds after detection)
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

If you need the raw (unmasked) text, click the menu bar icon and select "Copy Original Text". This is available for 30 seconds after detection.

Supported secret types: AWS, GitHub, Slack, GCP, Azure, npm, Docker, and [more](https://github.com/secretlint/secretlint/tree/master/packages/%40secretlint/secretlint-rule-preset-recommend#rules). You can also define custom patterns.

## Configuration

SecureClipboard uses secretlint for scanning. You can customize rules via the menu: "Open .secretlintrc.json".

Config file location: `~/.config/secure-clipboard/.secretlintrc.json`

The bundled secretlint binary includes two rules:

- [`@secretlint/secretlint-rule-preset-recommend`](https://github.com/secretlint/secretlint/tree/master/packages/%40secretlint/secretlint-rule-preset-recommend) — detects AWS, GitHub, Slack, GCP, Azure, npm, Docker, and other common secrets
- [`@secretlint/secretlint-rule-pattern`](https://github.com/secretlint/secretlint/tree/master/packages/%40secretlint/secretlint-rule-pattern) — detects custom patterns defined by regex

You can add custom patterns to detect arbitrary text:

```json
{
    "rules": [
        {
            "id": "@secretlint/secretlint-rule-preset-recommend"
        },
        {
            "id": "@secretlint/secretlint-rule-pattern",
            "options": {
                "patterns": [
                    {
                        "name": "credentials",
                        "pattern": "/MY_SECRET_VALUE/"
                    }
                ]
            }
        }
    ]
}
```

Config changes are picked up on the next clipboard copy — no restart required.

## CLI Tools

SecureClipboard bundles `secure-pbpaste` and `secure-pbcopy` — drop-in replacements for `pbpaste` and `pbcopy` that automatically mask secrets.

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
