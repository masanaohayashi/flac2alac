FLAC to ALAC (M4A) Converter CLI

概要
- FLACファイルを ALAC(Apple Lossless) コーデックの M4A に変換するシンプルなCLIです。
- 可能な限りメタデータとアートワークを維持します（ffmpeg使用時）。
- ffmpeg が推奨、macOS で afconvert もサポートします（メタデータ保持は限定的）。

前提
- Python 3.8+
- いずれかの変換コマンド
  - ffmpeg（推奨）
  - afconvert（macOS標準。メタデータ保持は限定的）

使い方

1) ヘルプ

  python3 flac2alac.py -h

2) ディレクトリ配下を変換し、./alac 以下にミラー出力（デフォルト）

  python3 flac2alac.py /path/to/music

3) 入力と同じ場所に出力（.flac → .m4a）

  python3 flac2alac.py --inplace /path/to/song.flac

4) 出力ディレクトリを明示

  python3 flac2alac.py -o /path/to/output /path/to/music

5) 既存ファイルを上書き

  python3 flac2alac.py -f /path/to/music

6) 並列ワーカー数を調整

  python3 flac2alac.py -w 8 /path/to/music

7) ドライラン（何が変換されるか確認）

  python3 flac2alac.py -n /path/to/music

8) アートワークを無効化

  python3 flac2alac.py --no-art /path/to/music

9) afconvert を優先（macOS）

  python3 flac2alac.py --prefer-afconvert /path/to/music

10) 変換後の可逆性を検証（PCM MD5比較）

  python3 flac2alac.py --verify /path/to/music

  備考: 検証には ffmpeg が必要です。afconvertで変換した場合でも、ffmpeg があれば検証可能です。不一致時は失敗として扱い、生成したM4Aを削除します。

11) 変換後に元FLACを削除（注意！）

  python3 flac2alac.py --delete-original /path/to/music

備考
- ffmpeg使用時は `-c:a alac -map_metadata 0 -movflags use_metadata_tags` を指定し、可能であればカバーアートを `attached_pic` として埋め込みます。
- 一部のFLACではカバーアートの抽出/埋め込みが行えない場合があります。
- afconvertではメタデータやアートワークの引き継ぎは限定的です。必要に応じてffmpegをインストールしてください。
- 既存出力が新しければスキップします。`-f` をつけると強制上書きします。

ライセンス
- このリポジトリ内のスクリプトはパブリックドメイン相当で自由に利用可能です（明示的な表記不要）。
