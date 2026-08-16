#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 KPOP之王巔峰賽 — 第三關「看舞蹈猜歌」自動題目產生器
=============================================================================

用途
----
把原版 MV 丟進「第三關_看舞蹈猜歌\\原始MV\\」資料夾，執行本腳本後會自動輸出：

    第三關_看舞蹈猜歌\\題目\\<團體_歌名>.mp4   ← 人物全黑剪影 + 已抽離音訊
    第三關_看舞蹈猜歌\\答案\\<團體_歌名>.mp4   ← 原版影片（可選壓縮）

最後自動呼叫 scan_assets.ps1 重新產生 quiz-data.js，題庫立刻多一題。

兩種引擎
--------
  --engine ffmpeg     （預設，最穩）只需要 ffmpeg。用亮度門檻把畫面壓成
                      黑白剪影，速度快、100% 可預期，不需要 AI 模型。
  --engine mediapipe  用 MediaPipe 人物分割做「真・去背剪影」：人物塗全黑、
                      背景留白，完全看不出服裝與場景。需要 opencv + mediapipe。
                      找不到套件時會自動退回 ffmpeg 引擎。

安裝
----
    ffmpeg：https://www.gyan.dev/ffmpeg/builds/  下載後把 bin 加進 PATH
    AI 引擎（可選）： pip install -r requirements.txt

用法範例
--------
    python make_silhouette.py
    python make_silhouette.py --engine mediapipe
    python make_silhouette.py --threshold 130 --maxwidth 720
    python make_silhouette.py --input "D:\\下載\\新MV" --clip 0 45
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

VIDEO_EXT = {".mp4", ".mov", ".mkv", ".webm", ".m4v", ".avi", ".ts"}


# --------------------------------------------------------------------------
# 共用小工具
# --------------------------------------------------------------------------
def log(msg, tag="·"):
    print(f"  {tag} {msg}", flush=True)


def find_ffmpeg():
    for name in ("ffmpeg", "ffmpeg.exe"):
        p = shutil.which(name)
        if p:
            return p
    # 常見的 Windows 安裝位置
    for guess in (
        r"C:\ffmpeg\bin\ffmpeg.exe",
        r"C:\Program Files\ffmpeg\bin\ffmpeg.exe",
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe"),
    ):
        if os.path.isfile(guess):
            return guess
    return None


def run(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout.decode("utf-8", "ignore")[-3000:] + "\n")
        raise RuntimeError("指令失敗： " + " ".join(str(c) for c in cmd[:4]) + " ...")
    return proc


def resolve_root(explicit=None):
    """回傳 D:\\kpop（素材根目錄）"""
    if explicit:
        return Path(explicit).resolve()
    # 本檔位於 <root>/app/scripts/make_silhouette.py
    return Path(__file__).resolve().parents[2]


def find_level3_dir(root):
    for d in sorted(root.iterdir()):
        if d.is_dir() and (d.name.startswith("第三關") or d.name.lower().startswith("level3") or "舞蹈" in d.name):
            return d
    raise SystemExit(f"找不到第三關資料夾（{root} 底下應該要有「第三關_看舞蹈猜歌」）")


# --------------------------------------------------------------------------
# 引擎 A：純 ffmpeg 亮度門檻剪影（無需 AI，速度快）
# --------------------------------------------------------------------------
def build_ffmpeg_filter(threshold, blur, maxwidth, invert):
    """
    畫面 → 灰階 → 輕微模糊（吃掉細節）→ 亮度門檻二值化 → 黑白剪影
    """
    dark, light = (235, 16) if invert else (16, 235)
    parts = [f"scale={maxwidth}:-2:flags=bicubic", "format=gray"]
    if blur > 0:
        parts.append(f"boxblur={blur}:1")
    parts.append(f"lutyuv=y='if(lt(val,{threshold}),{dark},{light})'")
    parts.append("format=yuv420p")
    return ",".join(parts)


def make_question_ffmpeg(ffmpeg, src, dst, args):
    vf = build_ffmpeg_filter(args.threshold, args.blur, args.maxwidth, args.invert)
    cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error"]
    if args.clip:
        cmd += ["-ss", str(args.clip[0]), "-t", str(args.clip[1] - args.clip[0])]
    cmd += ["-i", str(src), "-an", "-vf", vf,
            "-c:v", "libx264", "-preset", "veryfast", "-crf", str(args.crf),
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(dst)]
    run(cmd)


# --------------------------------------------------------------------------
# 引擎 B：MediaPipe 人物分割 → 真・全黑剪影
# --------------------------------------------------------------------------
def make_question_mediapipe(ffmpeg, src, dst, args):
    import cv2
    import numpy as np
    import mediapipe as mp

    cap = cv2.VideoCapture(str(src))
    if not cap.isOpened():
        raise RuntimeError(f"無法開啟影片：{src}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    src_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    src_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if src_w == 0:
        raise RuntimeError("讀不到影片尺寸")

    out_w = min(args.maxwidth, src_w)
    out_h = int(round(out_w * src_h / src_w / 2) * 2)

    start_f = int((args.clip[0] if args.clip else 0) * fps)
    end_f = int((args.clip[1] if args.clip else 10 ** 9) * fps)
    if start_f:
        cap.set(cv2.CAP_PROP_POS_FRAMES, start_f)

    tmp = Path(tempfile.gettempdir()) / (dst.stem + "__raw.mp4")
    writer = cv2.VideoWriter(str(tmp), cv2.VideoWriter_fourcc(*"mp4v"), fps, (out_w, out_h))

    seg = mp.solutions.selfie_segmentation.SelfieSegmentation(model_selection=1)
    bg = np.full((out_h, out_w, 3), 245, dtype=np.uint8)   # 背景：近白
    fg = np.zeros((out_h, out_w, 3), dtype=np.uint8)       # 人物：純黑

    n = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok or (start_f + n) > end_f:
                break
            frame = cv2.resize(frame, (out_w, out_h), interpolation=cv2.INTER_AREA)
            res = seg.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            mask = res.segmentation_mask
            mask = cv2.GaussianBlur(mask, (0, 0), 2.0)
            m3 = np.repeat((mask > args.seg_threshold)[:, :, None], 3, axis=2)
            writer.write(np.where(m3, fg, bg))
            n += 1
            if n % 120 == 0:
                log(f"已處理 {n} 幀…", "→")
    finally:
        cap.release()
        writer.release()
        seg.close()

    if n == 0:
        raise RuntimeError("沒有讀到任何影格")

    # 轉成瀏覽器友善的 H.264（cv2 輸出的 mp4v 在部分瀏覽器播不動）
    run([ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", str(tmp),
         "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", str(args.crf),
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(dst)])
    tmp.unlink(missing_ok=True)


# --------------------------------------------------------------------------
# 答案影片
# --------------------------------------------------------------------------
def make_answer(ffmpeg, src, dst, args):
    if args.answer_maxwidth <= 0 and src.suffix.lower() == ".mp4":
        shutil.copy2(src, dst)
        return
    cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error"]
    if args.clip:
        cmd += ["-ss", str(args.clip[0]), "-t", str(args.clip[1] - args.clip[0])]
    cmd += ["-i", str(src)]
    if args.answer_maxwidth > 0:
        cmd += ["-vf", f"scale='min({args.answer_maxwidth},iw)':-2"]
    cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", str(args.answer_crf),
            "-c:a", "aac", "-b:a", "160k", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", str(dst)]
    run(cmd)


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="把原版 MV 自動轉成第三關的黑影題目影片 + 答案影片",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", help="素材根目錄，預設自動推算為 D:\\kpop")
    ap.add_argument("--input", help="原版 MV 來源資料夾，預設 <第三關>\\原始MV")
    ap.add_argument("--engine", choices=["ffmpeg", "mediapipe", "auto"], default="auto",
                    help="剪影引擎（auto = 有裝 mediapipe 就用 AI，否則用 ffmpeg）")
    ap.add_argument("--threshold", type=int, default=110, help="ffmpeg 引擎的亮度門檻 0-255（越大越黑）")
    ap.add_argument("--blur", type=float, default=2, help="ffmpeg 引擎二值化前的模糊強度")
    ap.add_argument("--invert", action="store_true", help="黑白反轉（亮背景 MV 適用）")
    ap.add_argument("--seg-threshold", type=float, default=0.45, help="mediapipe 分割門檻 0-1")
    ap.add_argument("--maxwidth", type=int, default=854, help="題目影片寬度上限")
    ap.add_argument("--crf", type=int, default=26, help="題目影片畫質（數字越小越清楚）")
    ap.add_argument("--answer-maxwidth", type=int, default=1280,
                    help="答案影片寬度上限（設 0 代表原檔直接複製不轉檔）")
    ap.add_argument("--answer-crf", type=int, default=23, help="答案影片畫質")
    ap.add_argument("--clip", nargs=2, type=float, metavar=("START", "END"),
                    help="只擷取某個秒數區間，例如 --clip 45 75")
    ap.add_argument("--overwrite", action="store_true", help="已存在的輸出檔也重做")
    ap.add_argument("--no-rescan", action="store_true", help="處理完不要自動重建題庫")
    args = ap.parse_args()

    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        raise SystemExit(
            "找不到 ffmpeg。\n"
            "請到 https://www.gyan.dev/ffmpeg/builds/ 下載 ffmpeg-release-essentials.zip，\n"
            "解壓縮後把裡面的 bin 資料夾加入系統 PATH，再重新執行。")

    root = resolve_root(args.root)
    lv3 = find_level3_dir(root)
    src_dir = Path(args.input) if args.input else (lv3 / "原始MV")
    q_dir = lv3 / "題目"
    a_dir = lv3 / "答案"
    src_dir.mkdir(parents=True, exist_ok=True)
    q_dir.mkdir(parents=True, exist_ok=True)
    a_dir.mkdir(parents=True, exist_ok=True)

    engine = args.engine
    if engine == "auto":
        try:
            import mediapipe  # noqa: F401
            import cv2        # noqa: F401
            engine = "mediapipe"
        except Exception:
            engine = "ffmpeg"
    elif engine == "mediapipe":
        try:
            import mediapipe  # noqa: F401
            import cv2        # noqa: F401
        except Exception:
            log("沒偵測到 mediapipe/opencv，改用 ffmpeg 引擎。", "!")
            engine = "ffmpeg"

    videos = sorted([p for p in src_dir.iterdir() if p.is_file() and p.suffix.lower() in VIDEO_EXT])

    print()
    print("=" * 58)
    print("  第三關 看舞蹈猜歌 — 自動剪影產生器")
    print("=" * 58)
    log(f"素材根目錄： {root}")
    log(f"來源資料夾： {src_dir}")
    log(f"剪影引擎  ： {engine}")
    log(f"待處理影片： {len(videos)} 支")
    print()

    if not videos:
        print(f"『{src_dir}』裡面沒有影片。")
        print("把原版 MV（檔名請用「團體_歌名.mp4」）放進去再執行一次即可。")
        return

    done = 0
    for v in videos:
        stem = v.stem
        q_out = q_dir / f"{stem}.mp4"
        a_out = a_dir / f"{stem}.mp4"
        log(f"處理中：{stem}", "▶")
        try:
            if q_out.exists() and not args.overwrite:
                log("題目影片已存在，略過（要重做請加 --overwrite）", "·")
            else:
                if engine == "mediapipe":
                    make_question_mediapipe(ffmpeg, v, q_out, args)
                else:
                    make_question_ffmpeg(ffmpeg, v, q_out, args)
                log(f"題目 → {q_out.name}", "✔")

            if a_out.exists() and not args.overwrite:
                log("答案影片已存在，略過", "·")
            else:
                make_answer(ffmpeg, v, a_out, args)
                log(f"答案 → {a_out.name}", "✔")
            done += 1
        except Exception as e:
            log(f"失敗：{e}", "✖")
        print()

    print(f"完成 {done}/{len(videos)} 支。")

    if not args.no_rescan:
        ps1 = root / "app" / "scripts" / "scan_assets.ps1"
        if ps1.exists() and os.name == "nt":
            log("重新掃描題庫…", "↻")
            subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ps1)])
        else:
            log("請手動執行「更新題庫.bat」讓新題目進入題庫。", "!")


if __name__ == "__main__":
    main()
