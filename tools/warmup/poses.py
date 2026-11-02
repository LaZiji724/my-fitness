"""没有照片的动作的示意图姿势表：每个动作两帧（开始 / 结束）。

key 与 catalog.py 里的 ILLUSTRATED 一致。姿势用 figure.Pose 的绝对角度描述。
需要「双手 + 脚/膝同时着地」的姿势（平板类）用 solve() 自动求躯干倾角。
"""
from __future__ import annotations

from figure import Pose, joints


def solve(fn, a=0.0, b=70.0, pair=("hand", "toe"), iters=40) -> Pose:
    """二分法找躯干角度 T，使 pair 两个关节离地一样高（y 相等）。fn(T) -> Pose。"""
    def diff(t):
        j = joints(fn(t))
        return j[pair[0]][1] - j[pair[1]][1]
    lo, hi = a, b
    flo = diff(lo)
    for _ in range(iters):
        mid = (lo + hi) / 2
        fm = diff(mid)
        if (fm > 0) == (flo > 0):
            lo, flo = mid, fm
        else:
            hi = mid
    return fn((lo + hi) / 2)


# ---------------------------------------------------------------- 常用姿势
def stand(**kw) -> Pose:
    return Pose(**{**dict(torso=90, arm=(270, 270), leg=(270, 270)), **kw})


def plank(arm_hand="hand", legs_bent=False) -> Pose:
    def f(t):
        return Pose(torso=t, arm=(270, 270), leg=(t + 180, t + 180), foot=t + 180 + 90 + 0)
    return solve(f, 5, 55, ("hand", "toe"))


def plank_forearm() -> Pose:
    def f(t):
        return Pose(torso=t, arm=(300, 0), leg=(t + 180, t + 180))
    return solve(f, 0, 40, ("hand", "toe"))


def quadruped(t=22, **kw) -> Pose:
    # 四点支撑：手撑地、膝着地；小腿向后平放
    def f(tt):
        return Pose(**{**dict(torso=tt, arm=(270, 270), leg=(270, 180), foot=270), **kw})
    return solve(f, 0, 50, ("hand", "kn"))


def supine(**kw) -> Pose:
    base = dict(torso=180, arm=(0, 0), leg=(0, 0), foot=90)
    return Pose(**{**base, **kw})


def bridge(**kw) -> Pose:
    """臀桥：肩背着地、髋顶起；躯干角度自动求解让肩和脚踝同高。"""
    def f(t):
        return Pose(**{**dict(torso=t, arm=(t + 15, t + 15), leg=(342, 278), foot=0), **kw})
    return solve(f, 185, 250, ("neck", "an"))


def supine_bent(**kw) -> Pose:
    base = dict(torso=180, arm=(0, 0), leg=(60, 293), foot=0)
    return Pose(**{**base, **kw})


def side_lying(**kw) -> Pose:
    base = dict(torso=180, arm=(90, 90), leg=(0, 0), foot=90)
    return Pose(**{**base, **kw})


def squat(depth=1.0, **kw) -> Pose:
    # depth 1.0 = 大腿略低于水平
    base = dict(torso=62, arm=(10, 10), leg=(352, 250), foot=0)
    return Pose(**{**base, **kw})


# ---------------------------------------------------------------- 姿势表
POSES: dict[str, tuple[Pose, Pose]] = {
    # 有氧 / 全身
    "fc_jumping_jack": (
        stand(),
        stand(arm=(82, 82), arm2=(62, 62), leg=(250, 256), leg2=(290, 284), foot=0, foot2=0),
    ),
    "fc_high_knees": (
        stand(torso=92, arm=(245, 345), arm2=(295, 40), leg=(8, 272), foot=0, leg2=(270, 270)),
        stand(torso=92, arm=(295, 40), arm2=(245, 345), leg=(270, 270), leg2=(8, 272), foot2=0),
    ),
    "fc_burpee": (
        plank(),
        stand(arm=(80, 80), arm2=(100, 100), leg=(268, 262), foot=0),
    ),
    "fc_shadow_boxing": (
        stand(torso=84, arm=(300, 75), arm2=(320, 85), leg=(292, 256), leg2=(252, 280), foot=0, foot2=0),
        stand(torso=80, arm=(3, 3), arm2=(320, 85), leg=(292, 256), leg2=(252, 280), foot=0, foot2=0),
    ),
    "fc_jump_squat_lowimpact": (
        squat(),
        stand(arm=(40, 40), leg=(8, 272), leg2=(270, 270), foot=0),
    ),
    "fc_step_jack": (
        stand(),
        stand(arm=(80, 80), arm2=(60, 60), leg=(300, 272), leg2=(255, 265), foot=0, foot2=0),
    ),
    "fc_tabata_mix": (
        squat(arm=(80, 80)),
        stand(arm=(80, 80), arm2=(100, 100), leg=(268, 262), foot=0),
    ),
    # 居家力量
    "fc_knee_pushup": (
        solve(lambda t: Pose(torso=t, arm=(270, 270), leg=(t + 176, 128), foot=0), 5, 60, ("hand", "kn")),
        solve(lambda t: Pose(torso=t, arm=(235, 300), leg=(t + 176, 128), foot=0), 2, 60, ("hand", "kn")),
    ),
    "fc_pike_pushup": (
        solve(lambda t: Pose(torso=t, arm=(270, 270), leg=(248, 250), head=t - 18, foot=0), 300, 359, ("hand", "toe")),
        solve(lambda t: Pose(torso=t, arm=(300, 300), leg=(248, 250), head=t - 40, foot=0), 300, 359, ("hand", "toe")),
    ),
    "fc_reverse_lunge": (
        stand(),
        Pose(torso=92, arm=(270, 270), leg=(335, 262), leg2=(222, 252), foot=0, foot2=300),
    ),
    "fc_bulgarian_split_squat": (
        Pose(torso=94, arm=(270, 270), leg=(278, 268), leg2=(190, 215), foot=0, foot2=270, props=[("bench", "an2")]),
        Pose(torso=94, arm=(270, 270), leg=(352, 262), leg2=(205, 215), foot=0, foot2=270, props=[("bench", "an2")]),
    ),
    "fc_wall_sit": (
        Pose(torso=90, arm=(0, 0), leg=(0, 270), foot=0, props=[("wall", "left")]),
        Pose(torso=90, arm=(20, 20), leg=(0, 270), foot=0, props=[("wall", "left")]),
    ),
    "fc_calf_raise_bw": (
        stand(arm=(300, 300)),
        stand(arm=(300, 300), foot=300),
    ),
    "fc_bird_dog": (
        quadruped(),
        solve(lambda t: Pose(torso=t, arm=(270, 270), arm2=(12, 12), leg=(270, 180), leg2=(186, 186), foot=270, foot2=270), 0, 40, ("hand", "kn")),
    ),
    "fc_hollow_hold": (
        supine(),
        Pose(torso=192, arm=(172, 172), leg=(14, 14), foot=100, head=206),
    ),
    "fc_plank_shoulder_tap": (
        plank(),
        solve(lambda t: Pose(torso=t, arm=(270, 270), arm2=(32, 120), leg=(t + 180, t + 180)), 5, 55, ("hand", "toe")),
    ),
    "fc_clamshell": (
        supine(torso=180, arm=(0, 0), leg=(25, 320), leg2=(25, 320), foot=0),
        supine(torso=180, arm=(0, 0), leg=(25, 320), leg2=(62, 335), foot=0, foot2=10),
    ),
    "fc_side_leg_raise": (
        supine(arm=(0, 0), leg=(0, 0), leg2=(0, 0)),
        supine(arm=(0, 0), leg=(0, 0), leg2=(38, 38), foot2=128),
    ),
    "fc_glute_bridge_march": (
        bridge(),
        bridge(leg2=(78, 10), foot2=90),
    ),
    "fc_frog_pump": (
        supine(torso=180, arm=(0, 0), leg=(52, 297), leg2=(52, 297), foot=0),
        bridge(leg=(342, 278)),
    ),
    "fc_cossack_squat": (
        stand(arm=(0, 0), leg=(255, 262), leg2=(285, 278), foot=0, foot2=0),
        Pose(torso=78, arm=(0, 0), leg=(342, 252), leg2=(232, 232), foot=0, foot2=60),
    ),
    "fc_straight_leg_raise": (
        supine(arm=(0, 0), leg=(0, 0), leg2=(58, 296), foot=90, foot2=0),
        supine(arm=(0, 0), leg=(42, 42), leg2=(58, 296), foot=132, foot2=0),
    ),
    "fc_dead_hang": (
        Pose(torso=90, arm=(90, 90), leg=(270, 270), foot=0, props=[("bar",)]),
        Pose(torso=90, arm=(90, 90), leg=(262, 262), leg2=(278, 278), foot=0, props=[("bar",)]),
    ),
    "fc_wall_angel": (
        Pose(torso=90, arm=(270, 75), leg=(270, 270), foot=0, props=[("wall", "left")]),
        Pose(torso=90, arm=(100, 100), leg=(270, 270), foot=0, props=[("wall", "left")]),
    ),
    "fc_prone_ytw": (
        Pose(torso=3, arm=(0, 0), leg=(180, 180), foot=270, head=10),
        Pose(torso=8, arm=(25, 25), leg=(186, 186), foot=270, head=24),
    ),
    "fc_scapular_pushup": (
        solve(lambda t: Pose(torso=t, arm=(270, 270), leg=(t + 180, t + 180), head=t + 5), 5, 55, ("hand", "toe")),
        solve(lambda t: Pose(torso=t, arm=(270, 270), leg=(t + 180, t + 180), head=t - 28), 5, 55, ("hand", "toe")),
    ),
    "fc_chin_tuck": (
        stand(torso=90, head=64, props=[("wall", "left")]),
        stand(torso=90, head=90, props=[("wall", "left")]),
    ),
    "fc_single_leg_balance": (
        stand(arm=(0, 0), leg2=(270, 270), leg=(300, 255), foot=0),
        stand(arm=(40, 40), leg2=(270, 270), leg=(300, 255), foot=0),
    ),
    # 拉伸 / 活动度
    "fc_pigeon_stretch": (
        Pose(torso=95, arm=(270, 270), leg=(335, 190), leg2=(195, 185), foot=0, foot2=270, head=95),
        Pose(torso=22, arm=(350, 350), leg=(335, 190), leg2=(195, 185), foot=0, foot2=270, head=10),
    ),
    "fc_thoracic_rotation": (
        solve(lambda t: Pose(torso=t, arm=(270, 270), arm2=(140, 215), leg=(270, 180), foot=270), 0, 50, ("hand", "kn")),
        solve(lambda t: Pose(torso=t, arm=(270, 270), arm2=(90, 90), leg=(270, 180), foot=270), 0, 50, ("hand", "kn")),
    ),
    "fc_cobra_stretch": (
        Pose(torso=4, arm=(240, 8), leg=(180, 180), foot=270, head=6),
        Pose(torso=42, arm=(262, 262), leg=(180, 180), foot=270, head=48),
    ),
    "fc_9090_hip": (
        Pose(torso=95, arm=(0, 0), leg=(5, 265), leg2=(190, 95), foot=0, foot2=185),
        Pose(torso=95, arm=(0, 0), leg=(175, 85), leg2=(350, 265), foot=185, foot2=0),
    ),
    "fc_ankle_dorsiflexion": (
        Pose(torso=90, arm=(40, 40), leg=(325, 255), leg2=(240, 240), foot=0, foot2=300, props=[("wall", "right")]),
        Pose(torso=95, arm=(40, 40), leg=(335, 238), leg2=(240, 240), foot=0, foot2=300, props=[("wall", "right")]),
    ),
    "wu_wall_knee_drive": (
        Pose(torso=90, arm=(40, 40), leg=(270, 270), foot=0, props=[("wall", "right")]),
        Pose(torso=90, arm=(40, 40), leg2=(270, 270), leg=(0, 270), foot=0, props=[("wall", "right")]),
    ),
    "wu_tibialis_raise": (
        Pose(torso=95, arm=(270, 270), leg=(278, 278), foot=0, props=[("wall", "left")]),
        Pose(torso=95, arm=(270, 270), leg=(278, 278), foot=35, props=[("wall", "left")]),
    ),
}
