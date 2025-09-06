#!/usr/bin/env python3
from __future__ import annotations

import argparse
import concurrent.futures as cf
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


SUPPORTED_INPUT_EXTS = {".flac"}
OUTPUT_EXT = ".m4a"  # ALAC in MP4/M4A container


@dataclass
class Options:
    output_dir: Optional[Path]
    inplace: bool
    overwrite: bool
    dry_run: bool
    workers: int
    keep_artwork: bool
    prefer_afconvert: bool
    ffmpeg_path: Optional[str]
    delete_original: bool
    verify: bool
    ffmpeg_for_verify: Optional[str]


def log(msg: str) -> None:
    print(msg, flush=True)


def warn(msg: str) -> None:
    print(f"[WARN] {msg}", file=sys.stderr, flush=True)


def err(msg: str) -> None:
    print(f"[ERROR] {msg}", file=sys.stderr, flush=True)


def which_ffmpeg(explicit: Optional[str]) -> Optional[str]:
    if explicit:
        return explicit if shutil.which(explicit) else None
    return shutil.which("ffmpeg")


def which_afconvert() -> Optional[str]:
    return shutil.which("afconvert")


def detect_converter(prefer_afconvert: bool, ffmpeg_path: Optional[str]) -> Tuple[str, str]:
    """
    戻り値: (kind, path)
    kind: "ffmpeg" もしくは "afconvert"
    見つからなければ例外
    """
    ff = which_ffmpeg(ffmpeg_path)
    af = which_afconvert()

    if prefer_afconvert and af:
        return ("afconvert", af)
    if ff:
        return ("ffmpeg", ff)
    if af:
        warn("ffmpegが見つかりませんでしたが、afconvertを使用します（メタデータ保持は限定的です）")
        return ("afconvert", af)
    raise RuntimeError("ffmpeg または afconvert が見つかりません。インストールしてください。")


def build_ffmpeg_cmd(ffmpeg: str, src: Path, dst: Path, overwrite: bool, keep_artwork: bool) -> List[str]:
    cmd: List[str] = [ffmpeg]
    cmd += ["-hide_banner", "-loglevel", "error"]
    cmd += ["-y" if overwrite else "-n"]
    cmd += ["-i", str(src)]
    # 音声はALACに変換、メタデータを可能な限りコピー
    # アートワークは可能なら添付（なければ無視）
    if keep_artwork:
        cmd += [
            "-map", "0:a:0",
            "-c:a", "alac",
            "-map", "0:v?",
            "-c:v", "copy",
            "-disposition:v:0", "attached_pic",
            "-map_metadata", "0",
            "-movflags", "use_metadata_tags",
        ]
    else:
        cmd += [
            "-map", "0:a:0",
            "-c:a", "alac",
            "-map_metadata", "0",
            "-movflags", "use_metadata_tags",
        ]
    cmd += [str(dst)]
    return cmd


def build_afconvert_cmd(afconvert: str, src: Path, dst: Path, overwrite: bool) -> List[str]:
    # afconvert は上書きフラグがないため、事前に削除（呼び出し側で制御）
    # メタデータやアートワークの保持は限定的。
    return [afconvert, "-f", "m4af", "-d", "alac", str(src), str(dst)]


def ensure_parent_dir(p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)


def compute_output_path(src: Path, opts: Options, input_root: Optional[Path]) -> Path:
    out_name = src.with_suffix(OUTPUT_EXT).name
    if opts.inplace:
        return src.with_suffix(OUTPUT_EXT)
    assert opts.output_dir is not None
    if input_root is None:
        return opts.output_dir / out_name
    rel = src.relative_to(input_root)
    return opts.output_dir / rel.with_suffix(OUTPUT_EXT)


def should_skip(src: Path, dst: Path, overwrite: bool) -> bool:
    if overwrite:
        return False
    if not dst.exists():
        return False
    # 入力が新しければ変換、そうでなければスキップ
    try:
        return dst.stat().st_mtime >= src.stat().st_mtime
    except FileNotFoundError:
        return False


def gather_inputs(paths: List[Path]) -> List[Path]:
    files: List[Path] = []
    for p in paths:
        if p.is_file() and p.suffix.lower() in SUPPORTED_INPUT_EXTS:
            files.append(p)
        elif p.is_dir():
            for f in p.rglob("*"):
                if f.is_file() and f.suffix.lower() in SUPPORTED_INPUT_EXTS:
                    files.append(f)
        else:
            warn(f"対象外: {p}")
    return sorted(files)


def compute_pcm_md5(ffmpeg: str, path: Path) -> str:
    """ffmpegでPCM(S32LE)にデコードし、MD5を返す。"""
    h = __import__("hashlib").md5()
    cmd = [
        ffmpeg,
        "-v", "error",
        "-i", str(path),
        "-map", "0:a:0",
        "-f", "s32le",
        "-",
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.stdout is not None
    try:
        for chunk in iter(lambda: proc.stdout.read(1024 * 1024), b""):
            h.update(chunk)
    finally:
        proc.stdout.close()
    proc.wait()
    if proc.returncode != 0:
        err_out = proc.stderr.read().decode(errors="ignore") if proc.stderr else ""
        raise RuntimeError(err_out.strip() or "PCMデコードに失敗")
    return h.hexdigest()


def convert_one(src: Path, opts: Options, detected: Tuple[str, str], input_root: Optional[Path]) -> Tuple[Path, Optional[Path], bool, str]:
    kind, bin_path = detected
    dst = compute_output_path(src, opts, input_root)

    if should_skip(src, dst, opts.overwrite):
        return (src, dst, True, "skip: 既に最新の出力が存在")

    if opts.dry_run:
        return (src, dst, True, "dry-run: 変換予定")

    ensure_parent_dir(dst)

    if kind == "ffmpeg":
        cmd = build_ffmpeg_cmd(bin_path, src, dst, opts.overwrite, opts.keep_artwork)
    else:
        # afconvert は上書き時に既存ファイルを削除
        if opts.overwrite and dst.exists():
            try:
                dst.unlink()
            except Exception as e:
                return (src, dst, False, f"出力の削除に失敗: {e}")
        cmd = build_afconvert_cmd(bin_path, src, dst, opts.overwrite)

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            if dst.exists() and dst.stat().st_size == 0:
                try:
                    dst.unlink()
                except Exception:
                    pass
            return (src, dst, False, proc.stderr.strip() or "変換に失敗")
    except FileNotFoundError:
        return (src, dst, False, f"コマンドが見つかりません: {cmd[0]}")
    except Exception as e:
        return (src, dst, False, str(e))

    # 検証（可能なら）
    if opts.verify:
        if not opts.ffmpeg_for_verify:
            warn("--verify 指定ですが ffmpeg が見つからないため検証をスキップします")
        else:
            try:
                md5_src = compute_pcm_md5(opts.ffmpeg_for_verify, src)
                md5_dst = compute_pcm_md5(opts.ffmpeg_for_verify, dst)
                if md5_src != md5_dst:
                    # 失敗とし、生成物は削除（混乱防止）
                    try:
                        if dst.exists():
                            dst.unlink()
                    except Exception:
                        pass
                    return (src, dst, False, "verify不一致: PCM MD5が一致しません")
            except Exception as e:
                return (src, dst, False, f"verify失敗: {e}")

    # 検証まで成功した場合にのみ、元ファイル削除
    if opts.delete_original:
        try:
            src.unlink()
        except Exception as e:
            warn(f"元ファイル削除に失敗: {src} ({e})")

    return (src, dst, True, "ok")


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(
        description="FLACをALAC(M4A)へ変換。メタデータ/アートワークを可能な限り保持。",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("inputs", nargs="*", help="入力ファイルまたはディレクトリ（省略時はカレント）")
    out_group = p.add_mutually_exclusive_group()
    out_group.add_argument("-o", "--output", type=Path, help="出力ディレクトリ（構造をミラー）")
    out_group.add_argument("--inplace", action="store_true", help="入力と同じ場所に出力")
    p.add_argument("-w", "--workers", type=int, default=os.cpu_count() or 4, help="並列ワーカー数")
    p.add_argument("-n", "--dry-run", action="store_true", help="実行せず計画のみ表示")
    p.add_argument("-f", "--overwrite", action="store_true", help="既存の出力を上書き")
    p.add_argument("--no-art", dest="keep_artwork", action="store_false", help="アートワークを埋め込まない")
    p.add_argument("--prefer-afconvert", action="store_true", help="可能ならafconvertを優先（macOS）")
    p.add_argument("--ffmpeg", dest="ffmpeg_path", help="使用するffmpegのパスを明示")
    p.add_argument("--delete-original", action="store_true", help="変換成功後に元FLACを削除（注意）")
    p.add_argument("--verify", action="store_true", help="変換後にPCM MD5で可逆性を検証")

    args = p.parse_args(argv)

    inputs: List[Path] = [Path(a) for a in (args.inputs or [Path.cwd()])]
    output_dir: Optional[Path] = args.output

    if not args.inplace and not output_dir:
        # デフォルトは ./alac
        output_dir = Path.cwd() / "alac"

    if args.inplace and output_dir:
        err("--inplace と --output は同時指定できません")
        return 2

    opts = Options(
        output_dir=output_dir,
        inplace=bool(args.inplace),
        overwrite=bool(args.overwrite),
        dry_run=bool(args.dry_run),
        workers=max(1, int(args.workers)),
        keep_artwork=bool(args.keep_artwork),
        prefer_afconvert=bool(args.prefer_afconvert),
        ffmpeg_path=args.ffmpeg_path,
        delete_original=bool(args.delete_original),
        verify=bool(args.verify),
        ffmpeg_for_verify=which_ffmpeg(args.ffmpeg_path),
    )

    try:
        detected = detect_converter(opts.prefer_afconvert, opts.ffmpeg_path)
    except RuntimeError as e:
        err(str(e))
        return 127

    files = gather_inputs(inputs)
    if not files:
        warn("FLACファイルが見つかりませんでした")
        return 0

    # 入力ルートの決定（単一ディレクトリ指定時はそれをルートとみなす）
    input_root: Optional[Path] = None
    if len(inputs) == 1 and inputs[0].is_dir():
        input_root = inputs[0].resolve()

    log(f"converter: {detected[0]} ({detected[1]})")
    log(f"targets: {len(files)} file(s)")

    results: List[Tuple[Path, Optional[Path], bool, str]] = []
    if opts.workers == 1:
        for f in files:
            results.append(convert_one(f, opts, detected, input_root))
    else:
        with cf.ThreadPoolExecutor(max_workers=opts.workers) as ex:
            futs = [ex.submit(convert_one, f, opts, detected, input_root) for f in files]
            for fut in cf.as_completed(futs):
                results.append(fut.result())

    ok = 0
    skipped = 0
    failed = 0
    for src, dst, success, msg in sorted(results, key=lambda r: str(r[0]).lower()):
        if msg.startswith("skip"):
            skipped += 1
            status = "SKIP"
        elif msg.startswith("dry-run"):
            status = "DRY"
        elif success:
            ok += 1
            status = "OK"
        else:
            failed += 1
            status = "FAIL"
        out = str(dst) if dst else "-"
        print(f"[{status}] {src} -> {out} {'' if success else '(' + msg + ')'}")

    log(f"done: {ok} ok, {skipped} skip, {failed} fail")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
