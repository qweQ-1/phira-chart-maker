#!/usr/bin/env python3
"""生成 1024x1024 App 图标（iOS 17 单尺寸图标，由 actool 自动缩放）"""
import os
from PIL import Image, ImageDraw

SIZE = 1024
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "PhiraMaker", "Assets.xcassets", "AppIcon.appiconset")


def lerp(a, b, t):
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))


def make_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (12, 10, 24, 255))
    d = ImageDraw.Draw(img)

    # 背景渐变：深紫 → 近黑
    top = (46, 22, 78)
    bottom = (10, 8, 20)
    for y in range(SIZE):
        d.line([(0, y), (SIZE, y)], fill=lerp(top, bottom, y / SIZE) + (255,))

    cx = cy = SIZE // 2

    # 发光判定线
    for w, alpha in [(30, 26), (20, 45), (11, 85), (5, 210)]:
        pad = 120
        d.line([(pad, cy + 150), (SIZE - pad, cy + 150)], fill=(255, 105, 180, alpha), width=w)

    # 音符：错开排布，避免重叠
    notes = [
        (cx - 300, cy - 60, (255, 92, 160)),
        (cx - 100, cy - 230, (110, 220, 255)),
        (cx + 130, cy - 110, (255, 190, 90)),
        (cx + 310, cy - 300, (150, 255, 190)),
    ]
    for nx, ny, color in notes:
        r = 46
        for gr in range(5, 0, -1):
            d.ellipse([nx - r - gr * 12, ny - r - gr * 12,
                       nx + r + gr * 12, ny + r + gr * 12],
                      fill=color + (14,))
        d.ellipse([nx - r, ny - r, nx + r, ny + r], fill=color + (255,))
        d.ellipse([nx - r // 2, ny - r // 2, nx - r // 8, ny - r // 8],
                  fill=(255, 255, 255, 80))
        # 下落轨迹
        d.line([(nx, ny + r), (nx, cy + 130)], fill=color + (80,), width=7)

    # 底部节拍刻度
    for i in range(-4, 5):
        x = cx + i * 72
        h = 36 if i % 2 == 0 else 18
        d.line([(x, SIZE - 120), (x, SIZE - 120 - h)], fill=(180, 170, 220, 120), width=6)

    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    icon = make_icon()
    path = os.path.join(OUT_DIR, "icon-1024.png")
    icon.convert("RGB").save(path, "PNG")
    print("已生成:", path, os.path.getsize(path), "字节")


if __name__ == "__main__":
    main()
