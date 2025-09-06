FLAC→ALAC GUI (SwiftUI, macOS)

概要
- SwiftUI製のシンプルなGUI。入力/出力の選択、上書き/検証/並列数などを指定して変換できます。
- 変換エンジンは `ffmpeg` または `afconvert`（macOS）を外部プロセスとして呼び出します。

構成
- `FLAC2ALACApp.swift`: SwiftUIアプリのエントリポイント
- `ContentView.swift`: 画面（入力/出力選択、オプション、進捗リスト）
- `Converter.swift`: 変換ロジック。ffmpeg/afconvert呼び出し、PCM MD5検証（`CryptoKit.Insecure.MD5`）

前提
- macOS 12+ 推奨（SwiftUI/Concurrency）
- Xcode 14+（目安）
- `ffmpeg`（推奨）: `brew install ffmpeg`
- もしくは `afconvert`（macOSに標準搭載）

ビルド方法（Xcodeプロジェクト作成）
1. Xcodeで「新規 > プロジェクト > App」を選択
2. Interface: SwiftUI, Language: Swift, プラットフォーム: macOS を選択
3. 作成されたテンプレートの `App` と `ContentView` を、本ディレクトリの `FLAC2ALACApp.swift` / `ContentView.swift` に置き換え
4. 新規Swiftファイルとして `Converter.swift` を追加し、内容を貼り付け
5. ビルド & 実行

使い方
- 入力: 「選択…」から `.flac` ファイルやディレクトリを複数選べます
- 出力: 「入力と同じ場所」か、任意の出力ディレクトリを選択
- オプション:
  - 既存出力を上書き: 既にある `.m4a` を強制的に置換
  - 可逆性を検証: 変換前後をPCMにデコードしてMD5比較（ffmpegが必要）
  - アートワーク維持: カバーアートを可能なら `attached_pic` として埋め込み
  - afconvert優先: ffmpegが無い/使いたくない場合
  - 並列数: CPUコア数程度が目安

注意
- 可逆性検証には `ffmpeg` が必要です（afconvert変換でも検証自体はffmpegで実行）。
- アートワークや特殊タグはファイルによっては移行されないことがあります。

