"""原创动作示意图渲染器：侧视火柴人（胶囊肢体），暖黑白三色，与动作库照片同一色调。

姿势用「各段肢体的绝对角度」描述（度，0=朝右，90=朝上，180=朝左，270=朝下），人物始终朝右。
渲染时自动落地（最低点贴地）、水平居中、必要时缩小，不需要手写坐标。
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from PIL import Image, ImageDraw

W, H = 640, 480
SS = 2  # 超采样倍数
BG = (246, 243, 238)       # #F6F3EE
FLOOR = (233, 228, 220)
INK = (28, 26, 25)         # #1C1A19
MID = (139, 133, 128)      # #8B8580
PALE = (201, 195, 187)

# 肢体长度（单位）
TORSO, NECK, HEAD_R = 92, 10, 16
UARM, FARM, HAND = 50, 46, 9
THIGH, SHANK, FOOT = 66, 62, 24
THICK = {"torso": 30, "arm": 12, "leg": 17, "head": HEAD_R}


@dataclass
class Pose:
    torso: float = 90
    head: float | None = None           # 头相对躯干方向，缺省沿躯干
    arm: tuple[float, float] = (270, 270)
    arm2: tuple[float, float] | None = None   # 远侧手臂（灰），缺省与近侧相同
    leg: tuple[float, float] = (270, 270)
    leg2: tuple[float, float] | None = None
    foot: float | None = None           # 近侧脚角度，缺省随小腿
    foot2: float | None = None
    props: list = field(default_factory=list)  # ("wall", side) / ("bench", joint) / ("bar",) / ("bell",) / ("none_floor",)


def P(**kw) -> Pose:
    return Pose(**kw)


def _vec(a: float, ln: float) -> tuple[float, float]:
    r = math.radians(a)
    return math.cos(r) * ln, -math.sin(r) * ln


def _add(p, v):
    return (p[0] + v[0], p[1] + v[1])


def joints(pose: Pose) -> dict[str, tuple[float, float]]:
    hip = (0.0, 0.0)
    neck = _add(hip, _vec(pose.torso, TORSO))
    head_dir = pose.torso if pose.head is None else pose.head
    head = _add(neck, _vec(head_dir, NECK + HEAD_R))
    out = {"hip": hip, "neck": neck, "head": head}
    for tag, arm, leg, foot in (
        ("", pose.arm, pose.leg, pose.foot),
        ("2", pose.arm2 or pose.arm, pose.leg2 or pose.leg, pose.foot2 if pose.foot2 is not None else pose.foot),
    ):
        sh = neck
        el = _add(sh, _vec(arm[0], UARM))
        wr = _add(el, _vec(arm[1], FARM))
        hd = _add(wr, _vec(arm[1], HAND))
        kn = _add(hip, _vec(leg[0], THIGH))
        an = _add(kn, _vec(leg[1], SHANK))
        fa = (leg[1] + 90) % 360 if foot is None else foot
        toe = _add(an, _vec(fa, FOOT))
        out.update({f"sh{tag}": sh, f"el{tag}": el, f"wr{tag}": wr, f"hand{tag}": hd,
                    f"kn{tag}": kn, f"an{tag}": an, f"toe{tag}": toe})
    return out


def render(pose: Pose, scale: float = 1.7, out_size=(W, H)) -> Image.Image:
    J = joints(pose)
    pts = list(J.values())
    minx, maxx = min(p[0] for p in pts) - 20, max(p[0] for p in pts) + 20
    maxy = max(p[1] for p in pts) + 12
    miny = min(p[1] for p in pts) - HEAD_R
    wall = next((p for p in pose.props if p[0] == "wall"), None)
    s = scale
    span_w, span_h = (maxx - minx) * s, (maxy - miny) * s
    fit = min(1.0, 560 / max(span_w, 1), 340 / max(span_h, 1))
    s *= fit
    floor_y = 410
    hang = any(p[0] == "bar" for p in pose.props)
    # 平移：水平居中、最低点贴地（悬垂时头顶对齐）
    cx = (minx + maxx) / 2
    ox = W / 2 - cx * s
    oy = floor_y - maxy * s if not hang else 150 - (miny * s)
    if wall:
        # 靠墙：墙在身体最靠后一点之外
        pass

    def T(p):
        return ((p[0] * s + ox) * SS, (p[1] * s + oy) * SS)

    img = Image.new("RGB", (W * SS, H * SS), BG)
    d = ImageDraw.Draw(img)
    if not hang:
        d.rectangle([0, floor_y * SS, W * SS, H * SS], fill=FLOOR)
        d.line([0, floor_y * SS, W * SS, floor_y * SS], fill=PALE, width=3 * SS)
    # 道具（在人物后面）
    for pr in pose.props:
        if pr[0] == "wall":
            side = pr[1]
            xs = [p[0] for p in pts]
            x = (min(xs) - 14) if side == "left" else (max(xs) + 14)
            X = (x * s + ox) * SS
            d.rectangle([X - (0 if side == "right" else 28 * SS), 0, X + (28 * SS if side == "right" else 0), floor_y * SS], fill=FLOOR)
            d.line([X, 0, X, floor_y * SS], fill=PALE, width=3 * SS)
        elif pr[0] == "bench":
            jn = T(J[pr[1]])
            top = jn[1] + 6 * s * SS
            d.rounded_rectangle([jn[0] - 70 * s * SS, top, jn[0] + 70 * s * SS, top + 14 * s * SS], radius=6 * SS, fill=PALE)
            for dx in (-54, 54):
                d.rectangle([jn[0] + dx * s * SS - 5 * s * SS, top + 14 * s * SS, jn[0] + dx * s * SS + 5 * s * SS, floor_y * SS], fill=PALE)
        elif pr[0] == "bar":
            hw = T(J["hand"])
            d.rounded_rectangle([hw[0] - 150 * SS, hw[1] - 7 * s * SS, hw[0] + 150 * SS, hw[1] - 1 * s * SS], radius=4 * SS, fill=MID)
            d.rectangle([hw[0] + 140 * SS, hw[1] - 7 * s * SS, hw[0] + 150 * SS, (hw[1] + 150 * SS)], fill=PALE)
    def seg(a, b, w, col, halo=False):
        A, B = T(a), T(b)
        for ww, cc in (((w + 5) if halo else None, BG), (w, col)):
            if ww is None:
                continue
            r = ww * s * SS / 2
            d.line([A, B], fill=cc, width=int(ww * s * SS))
            for P_ in (A, B):
                d.ellipse([P_[0] - r, P_[1] - r, P_[0] + r, P_[1] + r], fill=cc)

    # 远侧肢体（灰）→ 躯干/头 → 近侧肢体（黑）
    seg(J["hip"], J["kn2"], THICK["leg"], MID); seg(J["kn2"], J["an2"], THICK["leg"] - 2, MID); seg(J["an2"], J["toe2"], 9, MID)
    seg(J["sh2"], J["el2"], THICK["arm"], MID); seg(J["el2"], J["hand2"], THICK["arm"] - 1, MID)
    seg(J["hip"], J["neck"], THICK["torso"], INK)
    seg(J["hip"], J["kn"], THICK["leg"] + 1, INK); seg(J["kn"], J["an"], THICK["leg"] - 1, INK); seg(J["an"], J["toe"], 9, INK)
    hc = T(J["head"]); r = HEAD_R * s * SS
    d.ellipse([hc[0] - r, hc[1] - r, hc[0] + r, hc[1] + r], fill=INK)
    seg(J["neck"], _add(J["neck"], _vec(pose.torso if pose.head is None else pose.head, NECK + 4)), 12, INK)
    seg(J["sh"], J["el"], THICK["arm"] + 1, INK, True); seg(J["el"], J["hand"], THICK["arm"], INK, True)
    # 前景道具
    for pr in pose.props:
        if pr[0] == "bell":
            h = T(J["hand"]); r = 13 * s * SS
            d.ellipse([h[0] - r, h[1] - r * 0.2, h[0] + r, h[1] + r * 1.8], fill=MID)
    return img.resize(out_size, Image.LANCZOS)
