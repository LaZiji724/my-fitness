"""生成 Android 启动图标（自适应图标 + 旧版方形图标）。

用法：python3 tools/make_icon.py
输出：app/android/app/src/main/res/ 下的 mipmap-*/ic_launcher*.png、
      mipmap-anydpi-v26/ic_launcher.xml、values/ic_launcher_background.xml，
      以及 app/assets/icon/app_icon.png（1024 母版，后续做 iPhone 版可直接用）。
图形：橙色底 + 深色哑铃，颜色取自主题（accent #FF5B1F，ink #141416）。
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "app/android/app/src/main/res"
ACCENT = (255, 91, 31, 255)
INK = (20, 20, 22, 255)
SS = 4  # 超采样倍数，边缘更平滑


def dumbbell(size: int, scale: float) -> Image.Image:
    """透明底的哑铃，scale 控制占画面的比例（自适应图标的安全区约 66%）。"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = s * scale / 100  # 以 100 为单位的网格
    cx = cy = s / 2

    def rr(x0, y0, x1, y1, r):
        d.rounded_rectangle([cx + x0 * u, cy + y0 * u, cx + x1 * u, cy + y1 * u], radius=r * u, fill=INK)

    rr(-30, -4.5, 30, 4.5, 3)         # 杆
    rr(-26, -22, -17, 22, 4)           # 左内片
    rr(17, -22, 26, 22, 4)             # 右内片
    rr(-36, -15, -27.5, 15, 3.5)       # 左外片
    rr(27.5, -15, 36, 15, 3.5)         # 右外片
    return img.resize((size, size), Image.LANCZOS)


def legacy(size: int) -> Image.Image:
    """旧版方形图标：圆角橙色底 + 哑铃。"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 0.22, fill=ACCENT)
    img = img.resize((size, size), Image.LANCZOS)
    img.alpha_composite(dumbbell(size, 0.86))
    return img


def main() -> None:
    legacy_sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    fg_sizes = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for dpi, px in legacy_sizes.items():
        d = RES / f"mipmap-{dpi}"
        d.mkdir(parents=True, exist_ok=True)
        legacy(px).save(d / "ic_launcher.png")
    for dpi, px in fg_sizes.items():
        # 自适应前景：整张 108dp，内容放在中间 66% 安全区内
        dumbbell(px, 0.66).save(RES / f"mipmap-{dpi}" / "ic_launcher_foreground.png")

    (RES / "values").mkdir(parents=True, exist_ok=True)
    (RES / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#FF5B1F</color>\n</resources>\n')
    (RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
    (RES / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')

    master = ROOT / "app/assets/icon"
    master.mkdir(parents=True, exist_ok=True)
    big = Image.new("RGBA", (1024, 1024), ACCENT)
    big.alpha_composite(dumbbell(1024, 0.86))
    big.convert("RGB").save(master / "app_icon.png")
    print("ok")


if __name__ == "__main__":
    main()
