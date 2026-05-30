# クリップボード自動クリア機能 設計

## 背景と目的

コピー&ペースト時に、過去にコピーした古い内容を誤ってペーストしてしまうことがある。これを防ぐため、最後のコピー（クリップボード変更）から一定時間が経過したらクリップボードを自動でクリアするオプションを追加する。

1Password の自動クリア（90秒）と同じ「アイドルベース」のモデルを採用する。既存の `copyOriginalText` が持つ90秒自動クリアの仕組みを、クリップボード全体に広げる位置づけ。

## クリアのモデル

- 「最後のコピーからN秒後」モデル（アイドルベース）。
- クリップボードが変更されるたびにタイマーが実質的にリセットされ、最後の変更からN秒経過したらクリアする。
- N秒以内に新しいコピーがあれば、古い予約は無効化され、最新の内容に対して新たに予約される。

## config 仕様

`~/.config/secure-clipboard/config.json` に新しいキーを追加する。

- キー名: `clearClipboardAfterSeconds`
- 型: `Double?`
- デフォルト: `nil`（機能無効）
- 挙動: 正の値が設定されたとき、その秒数後にクリップボードを自動クリアする。`nil`・`0`・負値はすべて「無効」として扱う。

`AppConfig` に `var clearClipboardAfterSeconds: Double?` を追加し、`AppConfig.default` と `load()` のフォールバックに反映する（既存の `scanDelaySeconds` と同じ流儀）。

`MenuBarView` の `defaultConfig` テンプレート文字列、および README / CLAUDE.md の config 例にも追記する。

UI（メニューのトグルや手動クリアボタン）は今回追加しない。設定は config.json のみで行う。

## スケジュール位置（ClipboardMonitor）

実装は `ClipboardMonitor` のポーリングループ内で行う（アプローチA）。

- 新しい変更を検出したブロック内で、クリアを予約する。
- 予約は `skipScanAppIdentifiers` による `continue` の**前**に行う。スキャン除外対象のアプリからのコピーも「古い内容を残さない」対象に含めるため。スキャン除外とクリア除外は別概念として扱い、結合しない。
- 予約はスキャン/マスク処理の**後**、つまり処理サイクルの最後に、その時点の `pasteboard.changeCount` を捕捉して行う。これにより外部コピーだけでなく SecureClipboard 自身がマスク・破棄で書き換えた内容も対象になる。
- 発火は `DispatchQueue.main.asyncAfter(deadline: .now() + N)` を使う。発火時に `pasteboard.changeCount == 捕捉値` の場合のみ `clearContents()` を実行する。一致しない場合（その後にコピーされた）は何もしない（no-op）。
- この changeCount ガード方式により、タイマーのキャンセル機構（DispatchWorkItem / Timer）は不要。古い予約は changeCount 不一致で自然に no-op になる。`copyOriginalText` と同じイディオム。

実装メモ: `skipScanAppIdentifiers` のスキップは現状 `continue` で早期離脱するため、クリア予約をそのブロックより前に移動する、もしくはクリア予約を専用ヘルパに切り出して両経路から呼べるようにする。

## 自己クリアループ防止（最重要）

`clearContents()` は `changeCount` を増加させる。何も対策しないと「クリア → 監視が新しい変更として検出 → 再予約 → クリア」が N秒ごとに無限に繰り返され、changeCount が変動し続けて他のクリップボードマネージャを妨害する恐れがある。

対策:

1. クリア実行後の新しい `changeCount` を、既存の `onCopy` / `recordOwnChange` 経路で自己書き込みとして記録する。監視ループはこれを無視するため、再予約されない。
2. 加えて、クリア発火時にクリップボードが既に空（対象タイプのデータが存在しない）であれば何もしない。

## マスク済み内容の扱い

スケジュールを処理サイクルの最後・マスク後の `changeCount` に対して行うため、外部からコピーされた内容だけでなく、SecureClipboard 自身がマスクした内容も N秒後にクリアされる。元の外部 `changeCount` に対して予約すると、マスクで count が変わりガードに失敗してマスク内容がクリアされないため、必ず処理後の count をキーにする。

## 既存の copyOriginalText との関係

`copyOriginalText` / `copyOriginalImage` の90秒自動クリアはそのまま据え置く。これは「意図的に元テキストを一時的に露出する」専用機能であり、固有のタイムアウトを持つ。今回の `clearClipboardAfterSeconds` には連動させず、独立した機能として維持する。

なお `copyOriginalText` のコピーは `recordOwnChange` で自己書き込みとして記録されるため、監視ループは新しい変更として検出せず、今回のクリア予約の対象にもならない。したがって両機能は干渉しない。

## テスト / 検証

CLAUDE.md の方針に従い、`swift test --disable-sandbox` と手動確認を行う。

自動テストの方針:

- `NSPasteboard.general` を書き込むテストは `@Suite(.serialized)` でラップして直列実行する（プロジェクト規約）。
- changeCount ガードのロジック（「捕捉した count と一致するときだけクリア」「空なら no-op」）を検証できる単位に切り出してテストする。

手動検証項目:

1. `clearClipboardAfterSeconds` に N を設定 → 何かをコピー → N秒後にクリップボードが空になる。
2. コピー → N秒以内に再コピー → 最新の内容のみがクリアされ、途中で古い内容が消えない。
3. 機能ON・何もコピーせず放置 → 無限クリアループが起きず、`changeCount` が安定している（ループバグ検出。最重要）。
