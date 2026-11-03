"""生成 iPhone 版图标与启动图（由 make_icon.py 产出的 1024 母版缩放而来）。

用法：python3 tools/make_icon.py && python3 tools/make_ios_icon.py
输出：app/ios/Runner/Assets.xcassets/ 下的 AppIcon.appiconset 与 LaunchImage.imageset。
iOS 图标必须是不透明方图（圆角由系统裁切），所以直接用母版缩放，不加圆角。
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "app/assets/icon/app_icon.png"
XC = ROOT / "app/ios/Runner/Assets.xcassets"


def main() -> None:
    master = Image.open(MASTER).convert("RGB")
    icons = XC / "AppIcon.appiconset"
    contents = json.loads((icons / "Contents.json").read_text())
    for item in contents["images"]:
        points = float(item["size"].split("x")[0])
        scale = int(item["scale"].rstrip("x"))
        px = round(points * scale)
        master.resize((px, px), Image.LANCZOS).save(icons / item["filename"])

    # 启动图：深色底（在 LaunchScreen.storyboard 里设置）上居中的圆角图标，逻辑尺寸 96pt。
    launch = XC / "LaunchImage.imageset"
    for scale, name in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")):
        px = 96 * scale
        ss = 4
        mask = Image.new("L", (px * ss, px * ss), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, px * ss - 1, px * ss - 1], radius=px * ss * 0.22, fill=255)
        mask = mask.resize((px, px), Image.LANCZOS)
        img = master.resize((px, px), Image.LANCZOS).convert("RGBA")
        img.putalpha(mask)
        img.save(launch / name)
    print("ok")


if __name__ == "__main__":
    main()
