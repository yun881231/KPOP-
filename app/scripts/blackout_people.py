#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 KPOP之王巔峰賽 — 第三關「看舞蹈猜歌」自動黑影產生器（AI 人物去背版）
=============================================================================

效果：**背景完全保留原樣，只把畫面中的人物塗成全黑剪影**，並抽掉音訊。
用的是 RVM (Robust Video Matting) 人物去背模型，專門為影片設計，
邊緣乾淨、逐格穩定不閃爍。

用法（由 產生第三關剪影.bat 自動呼叫，不必手動執行）：

    python blackout_people.py --input 原版MV.mp4 --question 題目.mp4 --answer 答案.mp4

參數：
    --hardness   0.0~1.0  邊緣硬度，越大剪影邊緣越銳利（預設 0.6）
    --dilate     像素     把黑色範圍向外擴張，可蓋掉頭髮邊緣殘影（預設 2）
    --ratio      0~1      模型內部縮放比例，越小越快（預設自動）
    --maxwidth   像素     輸出寬度上限（預設 1280）
    --crf        數字     輸出畫質，越小越清楚（預設 22）
"""

import argparse
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np
import onnxruntime as ort


def log(msg, tag="·"):
    print(f"  {tag} {msg}", flush=True)


def pick_ratio(w, h):
    """RVM 官方建議：長邊 <= 512 用 1.0，1080p 用 0.25，4K 用 0.125"""
    long_side = max(w, h)
    if long_side <= 512:
        return 1.0
    if long_side <= 1024:
        return 0.5
    if long_side <= 2048:
        return 0.25
    return 0.125


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--question", required=True)
    ap.add_argument("--answer")
    ap.add_argument("--model", default=None)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--hardness", type=float, default=0.6)
    ap.add_argument("--dilate", type=int, default=2)
    ap.add_argument("--ratio", type=float, default=0)
    ap.add_argument("--maxwidth", type=int, default=1280)
    ap.add_argument("--crf", type=int, default=22)
    ap.add_argument("--answer-crf", type=int, default=23)
    ap.add_argument("--fps", type=float, default=30, help="輸出影格率上限，越低處理越快（0=保持原始）")
    ap.add_argument("--start", type=float, default=-1)
    ap.add_argument("--end", type=float, default=-1)
    args = ap.parse_args()

    model = args.model or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                       "..", "models", "rvm_mobilenetv3_fp32.onnx")
    model = os.path.abspath(model)
    if not os.path.isfile(model):
        sys.exit(f"找不到模型檔：{model}")

    cap = cv2.VideoCapture(args.input)
    if not cap.isOpened():
        sys.exit(f"無法開啟影片：{args.input}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    sw = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    sh = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if sw == 0:
        sys.exit("讀不到影片尺寸")

    step = 1
    out_fps = fps
    if args.fps > 0 and fps > args.fps * 1.4:
        step = max(1, int(round(fps / args.fps)))
        out_fps = fps / step

    ow = min(args.maxwidth, sw)
    oh = int(round(ow * sh / sw / 2) * 2)
    ratio = args.ratio if args.ratio > 0 else pick_ratio(ow, oh)

    start_f = int(max(0, args.start) * fps) if args.start >= 0 else 0
    end_f = int(args.end * fps) if args.end > 0 else 10 ** 9
    if start_f:
        cap.set(cv2.CAP_PROP_POS_FRAMES, start_f)

    log(f"來源 {sw}x{sh} @ {fps:.2f}fps → 輸出 {ow}x{oh} @ {out_fps:.2f}fps，模型縮放 {ratio}")

    providers = ["CPUExecutionProvider"]
    try:
        if "CUDAExecutionProvider" in ort.get_available_providers():
            providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
    except Exception:
        pass
    so = ort.SessionOptions()
    so.log_severity_level = 3
    sess = ort.InferenceSession(model, so, providers=providers)

    rec = [np.zeros((1, 1, 1, 1), dtype=np.float32)] * 4
    ratio_t = np.array([ratio], dtype=np.float32)

    tmp = os.path.join(tempfile.gettempdir(), "kpop_q_raw.mp4")
    writer = cv2.VideoWriter(tmp, cv2.VideoWriter_fourcc(*"mp4v"), out_fps, (ow, oh))
    if not writer.isOpened():
        sys.exit("無法建立暫存影片")

    lo = 0.5 - (1.0 - args.hardness) * 0.35
    hi = 0.5 + (1.0 - args.hardness) * 0.35
    kernel = None
    if args.dilate > 0:
        k = args.dilate * 2 + 1
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))

    n = 0
    read_i = -1
    while True:
        ok, frame = cap.read()
        read_i += 1
        if not ok or (start_f + read_i) > end_f:
            break
        if read_i % step:
            continue
        if (frame.shape[1], frame.shape[0]) != (ow, oh):
            frame = cv2.resize(frame, (ow, oh), interpolation=cv2.INTER_AREA)

        src = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        src = np.transpose(src, (2, 0, 1))[None]

        fgr, pha, *rec = sess.run([], {
            "src": src, "r1i": rec[0], "r2i": rec[1], "r3i": rec[2], "r4i": rec[3],
            "downsample_ratio": ratio_t,
        })

        a = pha[0, 0]                                   # 0=背景 1=人物
        a = np.clip((a - lo) / max(1e-6, hi - lo), 0, 1)
        if kernel is not None:
            a = cv2.dilate(a, kernel)
            a = cv2.GaussianBlur(a, (0, 0), 0.8)
        a3 = a[:, :, None]

        # 背景原封不動，人物乘 0 → 全黑
        out = (frame.astype(np.float32) * (1.0 - a3)).astype(np.uint8)
        writer.write(out)

        n += 1
        if n % 60 == 0:
            pct = f" ({n * 100 // max(1, min(total, end_f - start_f))}%)" if total else ""
            log(f"已處理 {n} 幀{pct}", "→")

    cap.release()
    writer.release()
    if n == 0:
        sys.exit("沒有讀到任何影格")
    log(f"共 {n} 幀，轉檔中…", "→")

    # cv2 的 mp4v 在瀏覽器播不動，統一轉成 H.264 並確定沒有音軌
    subprocess.run([args.ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", tmp,
                    "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", str(args.crf),
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart", args.question], check=True)
    try:
        os.remove(tmp)
    except OSError:
        pass
    log(f"題目 → {os.path.basename(args.question)}", "✔")

    if args.answer:
        cmd = [args.ffmpeg, "-y", "-hide_banner", "-loglevel", "error"]
        if args.start >= 0:
            cmd += ["-ss", str(args.start)]
            if args.end > args.start:
                cmd += ["-t", str(args.end - args.start)]
        cmd += ["-i", args.input,
                "-vf", f"scale='min({args.maxwidth},iw)':-2",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", str(getattr(args, "answer_crf")),
                "-c:a", "aac", "-b:a", "160k", "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", args.answer]
        subprocess.run(cmd, check=True)
        log(f"答案 → {os.path.basename(args.answer)}", "✔")


if __name__ == "__main__":
    main()
