# SecureClipboard 設計仕様

## 概要

macOSメニューバー常駐アプリ。クリップボードにコピーされたテキスト・画像を自動でsecretlintでスキャンし、シークレットが含まれていればマスクしてクリップボードを上書きする。Secure by defaultなクリップボードを実現する。

## ユースケース

- パスワードや機密テキストを誤ってペーストすることを防ぐ
- 画像投稿時に機密情報が含まれていないかチェックする

## アーキテクチャ

```
┌─────────────────────────────────┐
│  SecureClipboard.app (SwiftUI)  │
│  メニューバー常駐               │
├─────────────────────────────────┤
│  ClipboardMonitor               │
│  SecretScanner                  │
│  ClipboardRewriter              │
│  StatusIndicator                │
└──────────┬──────────────────────┘
           │ subprocess (stdin/stdout)
           ▼
     secretlint (bunバイナリ)
```

### コンポーネント

**ClipboardMonitor**
- `NSPasteboard.general.changeCount` をポーリング（約500ms間隔）で監視
- テキスト変更検知時: SecretScannerにテキストを渡す
- 画像変更検知時: Vision frameworkでOCR → 抽出テキストをSecretScannerに渡す
- 自身によるクリップボード書き換え後のchangeCountを記録し、ループを防止する

**SecretScanner**
- secretlintバイナリをサブプロセスとして実行
- `secretlint --stdin --stdin-filename=clipboard.txt --format=json` でstdinからテキストを受け取る
- JSON結果から検出箇所の `range`（開始位置・終了位置）を解析して返す

**ClipboardRewriter**
- テキスト: 検出箇所を `***` に置換してクリップボードを上書き
- 画像: シークレット検出時に画像を赤塗り/警告画像で上書き
- 元データをメモリに一時保持（30秒後に自動破棄）

**StatusIndicator**
- メニューバーアイコン表示（SF Symbols `lock.shield`）
- シークレット検出時: アイコンを赤色に変化（数秒後に戻る）
- macOS通知:「クリップボードのシークレットをマスクしました」

## データフロー

1. ユーザーがテキスト/画像をコピー
2. ClipboardMonitorがchangeCount変化を検知
3. テキストの場合: そのままSecretScannerに渡す。画像の場合: Vision frameworkでOCR → テキスト抽出 → SecretScannerに渡す
4. SecretScannerがsecretlintバイナリを実行し、シークレットの有無と位置を返す
5. シークレット検出時:
   - ClipboardRewriterがマスク済みデータでクリップボードを上書き
   - 元データをメモリに一時保持
   - StatusIndicatorがアイコン赤化 + macOS通知
6. シークレット未検出時: 何もしない

## secretlintバイナリ連携

**バイナリ:**
- GitHubリリースの `secretlint-{version}-darwin-arm64` をアプリバンドル `Contents/Resources/` に同梱
- バージョンはアプリビルド時に固定

**設定:**
- バンドル内にデフォルトの `.secretlintrc.json` を同梱（`@secretlint/secretlint-rule-preset-recommend` を使用）
- ユーザーが `~/.config/secure-clipboard/.secretlintrc.json` を配置すれば上書き可能

## UI

**メニューバーアイコン:**
- 通常時: `lock.shield`（SF Symbols）
- 検出時: 赤色に変化（数秒後に戻る）

**メニュー内容:**
- 有効/無効トグル
- 直近の検出履歴（数件）
- 「元のデータをコピー」（検出直後のみ表示、30秒で消える）
- 設定（ポーリング間隔等）

**macOS通知:**
- シークレット検出時に通知を表示

## テスト方針

- ClipboardMonitor: changeCount変化の検知とループ防止をユニットテスト
- SecretScanner: secretlintバイナリの呼び出しと結果パースをユニットテスト
- ClipboardRewriter: マスク置換ロジックをユニットテスト
- 統合テスト: 既知のシークレットパターン（AWSキー、GitHubトークン等）をクリップボードにコピーし、マスクされることを確認

## スコープ外（将来対応）

- Windows/Linux対応
- クリップボード履歴マネージャー機能
- ファイルコピーのスキャン
- リッチテキスト対応
