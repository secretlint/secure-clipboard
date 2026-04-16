# SecureClipboard

macOSメニューバー常駐アプリ。クリップボードにコピーされたテキスト・画像を[secretlint](https://github.com/secretlint/secretlint)で自動スキャンし、シークレットが含まれていればマスクする。

## セットアップ

```bash
# secretlintバイナリをダウンロード
bash scripts/download-secretlint.sh <version>

# ビルド
swift build --disable-sandbox

# 実行
swift run --disable-sandbox
```

## 仕組み

1. クリップボードの変更をポーリングで監視（500ms間隔）
2. テキスト: secretlintでスキャンし、シークレット検出時にマスク済みテキストで上書き
3. 画像: Vision frameworkでOCR → secretlintでスキャン → 検出時に警告画像で上書き
4. メニューバーアイコンが赤くなり、macOS通知で知らせる

## テスト

```bash
swift test --disable-sandbox
```

## License

MIT
