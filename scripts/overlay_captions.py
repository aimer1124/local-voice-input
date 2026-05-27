#!/usr/bin/env python3
"""Overlay top/bottom captions onto an extracted frame sequence.

Configured entirely via env vars (set by make-demo-gif.sh):

  CAPTION_TOP, CAPTION_BOTTOM       Caption text (UTF-8). Empty = skip that band.
  CAPTION_TOP_RANGE = "start,end"   Visibility window in seconds (inclusive).
  CAPTION_BOTTOM_RANGE
  CAPTION_SIZE                       Font pixel size.
  CAPTION_FONT                       TTC/TTF font path (default macOS PingFang).
  FPS                                Frame rate used for second→frame mapping.
  FRAME_DIR                          Dir containing frame_NNNNN.png files (modified in place).
"""

import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def main() -> int:
    frame_dir = Path(os.environ["FRAME_DIR"])
    fps = float(os.environ.get("FPS", "15"))
    size = int(os.environ.get("CAPTION_SIZE", "28"))

    explicit_font = os.environ.get("CAPTION_FONT", "").strip()
    candidate_fonts = (
        [explicit_font] if explicit_font else []
    ) + [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]

    bands = []
    for band in ("TOP", "BOTTOM"):
        text = os.environ.get(f"CAPTION_{band}", "").strip()
        if not text:
            continue
        rng = os.environ.get(f"CAPTION_{band}_RANGE", "0,9999")
        start_s, end_s = (float(x) for x in rng.split(","))
        bands.append(
            {
                "position": band.lower(),
                "text": text,
                "start_frame": int(start_s * fps),
                "end_frame": int(end_s * fps),
            }
        )

    if not bands:
        print("无字幕需要叠加")
        return 0

    font = None
    for candidate in candidate_fonts:
        try:
            font = ImageFont.truetype(candidate, size)
            print(f"使用字体: {candidate}", file=sys.stderr)
            break
        except OSError:
            continue
    if font is None:
        print("⚠️  所有候选字体加载失败，回退默认（中文将显示方块）", file=sys.stderr)
        font = ImageFont.load_default()

    frames = sorted(frame_dir.glob("frame_*.png"))
    if not frames:
        print(f"❌ 没找到帧文件 in {frame_dir}", file=sys.stderr)
        return 1

    PADDING_X = 24
    PADDING_Y = 12
    EDGE_MARGIN = 32
    BG_ALPHA = 180  # 0–255

    for i, frame_path in enumerate(frames, start=1):
        img = Image.open(frame_path).convert("RGBA")
        overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        W, H = img.size

        for band in bands:
            if not (band["start_frame"] <= i <= band["end_frame"]):
                continue

            text = band["text"]
            bbox = draw.textbbox((0, 0), text, font=font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]

            box_w = tw + 2 * PADDING_X
            box_h = th + 2 * PADDING_Y
            box_x = (W - box_w) // 2

            if band["position"] == "top":
                box_y = EDGE_MARGIN
            else:
                box_y = H - box_h - EDGE_MARGIN

            draw.rounded_rectangle(
                (box_x, box_y, box_x + box_w, box_y + box_h),
                radius=12,
                fill=(0, 0, 0, BG_ALPHA),
            )
            draw.text(
                (box_x + PADDING_X, box_y + PADDING_Y - bbox[1]),
                text,
                fill=(255, 255, 255, 255),
                font=font,
            )

        composited = Image.alpha_composite(img, overlay).convert("RGB")
        composited.save(frame_path, "PNG", optimize=False)

    print(f"✅ 叠加完成: {len(frames)} 帧")
    return 0


if __name__ == "__main__":
    sys.exit(main())
