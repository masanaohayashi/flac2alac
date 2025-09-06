FLAC→ALAC GUI (SwiftUI, macOS)

概要
- SwiftUI製のシンプルなGUI。入力/出力の選択、上書き/検証/並列数などを指定して変換できます。
- 変換エンジンは `ffmpeg` または `afconvert`（macOS）を外部プロセスとして呼び出します。
 - ドラッグ＆ドロップに対応（.flac/ディレクトリ、カバー画像）

構成
- `FLAC2ALACApp.swift`: SwiftUIアプリのエントリポイント
- `ContentView.swift`: 画面（入力/出力選択、オプション、進捗リスト）
- `Converter.swift`: 変換ロジック。ffmpeg/afconvert呼び出し、PCM MD5検証（`CryptoKit.Insecure.MD5`）

前提
- macOS 12+ 推奨（SwiftUI/Concurrency）
- Xcode 14+（目安）
- `ffmpeg`（推奨）: `brew install ffmpeg`
- もしくは `afconvert`（macOSに標準搭載）

ビルド方法（同梱Xcodeプロジェクト）
1. `macos-app/FLAC2ALAC.xcodeproj` をXcodeで開く
2. ターゲット `FLAC2ALAC` を選び、SigningのTeamを自身のアカウントに設定
3. 実行（⌘R）

使い方
- 入力: 「選択…」から `.flac` ファイルやディレクトリを複数選べます
- 入力: ウィンドウに `.flac` またはディレクトリをドラッグ＆ドロップしても追加できます
- 出力: 「入力と同じ場所」か、任意の出力ディレクトリを選択
- 出力（デフォルト）: 未指定の場合はユーザーの「書類」フォルダに出力します
- オプション:
  - 既存出力を上書き: 既にある `.m4a` を強制的に置換
  - 可逆性を検証: 変換前後をPCMにデコードしてMD5比較（ffmpegが必要）
  - アートワーク維持: カバーアートを可能なら `attached_pic` として埋め込み
  - afconvert優先: ffmpegが無い/使いたくない場合
  - 並列数: CPUコア数程度が目安
- アートワーク: 画像（JPG/PNG）を指定またはドラッグ＆ドロップすると、全ファイルにその画像をカバーとして埋め込みます（ffmpeg使用時。afconvert時は後処理でffmpegが必要）

注意
- 可逆性検証には `ffmpeg` が必要です（afconvert変換でも検証自体はffmpegで実行）。
- アートワークや特殊タグはファイルによっては移行されないことがあります。
