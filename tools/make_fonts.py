#!/usr/bin/env python3
"""生成 App 内置字体（均为 SIL OFL 授权）。

- Noto Sans SC：从 Google Fonts 的可变字体切出 400/500/700 三个静态字重，
  并裁剪到 GB2312 常用汉字 + ASCII + 常用标点（体积从 17MB/份降到约 2–3MB/份），
  再补上 App 代码和内置数据里实际用到的字（如「腘」「−」「⌫」），保证界面里不出现回退字体。
- Barlow Condensed：直接下载 500/600/700 三个静态字重（数字专用，体积很小）。

用法：
  python3 -m venv .venv && .venv/bin/pip install fonttools brotli
  .venv/bin/python tools/make_fonts.py
输出到 app/assets/fonts/。
"""
import pathlib
import tempfile
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = pathlib.Path(__file__).resolve().parent.parent / "app" / "assets" / "fonts"
RAW = "https://raw.githubusercontent.com/google/fonts/main/ofl"


def fetch(url: str, dest: pathlib.Path) -> None:
    if dest.exists():
        return
    print("下载", url)
    urllib.request.urlretrieve(url, dest)


def gb2312_chars() -> str:
    chars = []
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.append(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return "".join(chars)


def app_chars() -> set[int]:
    """App 源码与内置数据（动作库、计划库）里出现的所有非 ASCII 字符。"""
    app = OUT.parent.parent
    files = [p for p in (app / "lib").rglob("*.dart") if not p.name.endswith(".g.dart")]
    files += list((app / "assets" / "seed").glob("*.json"))
    return {ord(c) for p in files for c in p.read_text(encoding="utf-8") if ord(c) > 0x7F}


def unicodes() -> list[int]:
    cps = set(ord(c) for c in gb2312_chars()) | app_chars()
    for a, b in [(0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x2190, 0x21FF),
                 (0x2460, 0x24FF), (0x25A0, 0x25FF), (0x2600, 0x26FF), (0x2700, 0x27BF),
                 (0x3000, 0x303F), (0xFF00, 0xFFEF)]:
        cps.update(range(a, b + 1))
    return sorted(cps)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        var = tmp / "NotoSansSC-VF.ttf"
        fetch(f"{RAW}/notosanssc/NotoSansSC%5Bwght%5D.ttf", var)
        for name, wght in [("Regular", 400), ("Medium", 500), ("Bold", 700)]:
            font = TTFont(var)
            inst = instancer.instantiateVariableFont(font, {"wght": wght})
            tmp_ttf = tmp / f"inst-{name}.ttf"
            inst.save(tmp_ttf)
            opts = subset.Options()
            opts.layout_features = ["*"]
            opts.name_IDs = ["*"]
            opts.notdef_outline = True
            opts.flavor = None
            f = subset.load_font(str(tmp_ttf), opts)
            s = subset.Subsetter(opts)
            s.populate(unicodes=unicodes())
            s.subset(f)
            dest = OUT / f"NotoSansSC-{name}.ttf"
            subset.save_font(f, str(dest), opts)
            print(dest.name, dest.stat().st_size // 1024, "KB")
        for w in ["Medium", "SemiBold", "Bold"]:
            dest = OUT / f"BarlowCondensed-{w}.ttf"
            fetch(f"{RAW}/barlowcondensed/BarlowCondensed-{w}.ttf", dest)
            print(dest.name, dest.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
