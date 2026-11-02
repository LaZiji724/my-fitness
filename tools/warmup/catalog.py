"""激活 / 拉伸动作的元数据与最终动作库合成。

做三件事：
1. 给计划库里已有的 86 个原创动作（fc_ 前缀）补上 类型 / 区域 / 默认计量 / 默认组数 / 配图来源；
2. 把 candidates.py 里的新动作（wu_ 前缀）转成动作库条目（和 fc_ 重复的合并，不重复入库）；
3. 给原有 235 个基础动作补上同样的字段，并按「更适合计时」的原则修正默认计量。

图片来源：
  PHOTO_FOR[slug]  free-exercise-db 的照片（The Unlicense），统一暖黑白处理
  poses.POSES      原创示意图（本目录 figure.py 渲染）
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from candidates import C  # noqa: E402

EXERCISE_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://my-fitness.local/exercise")

# ----------------------------------------------------------------------------- 类型
KINDS = ("strength", "cardio", "activation", "dynamic", "stretch", "foam")
REGIONS = ("neck_shoulder", "chest_arm", "back_core", "hip_glute", "leg", "full")

# fc_ 动作的类型（没列出的都是 strength）
KIND_OF: dict[str, str] = {}
for _s in ("treadmill_walk treadmill_incline_walk treadmill_jog treadmill_interval stair_climber rowing_machine "
           "elliptical stationary_bike jump_rope outdoor_walk outdoor_jog jumping_jack high_knees butt_kicks "
           "mountain_climber burpee squat_jump skater_hop shadow_boxing jump_squat_lowimpact step_jack tabata_mix").split():
    KIND_OF["fc_" + _s] = "cardio"
for _s in ("inchworm worlds_greatest_stretch leg_swing arm_circle hip_circle 9090_hip ankle_dorsiflexion "
           "thoracic_rotation ankle_circle cat_cow").split():
    KIND_OF["fc_" + _s] = "dynamic"
for _s in ("superman bird_dog clamshell fire_hydrant donkey_kick glute_bridge_march frog_pump wall_angel prone_ytw "
           "scapular_pushup chin_tuck band_external_rotation single_leg_balance hip_hinge_drill side_leg_raise").split():
    KIND_OF["fc_" + _s] = "activation"
for _s in ("childs_pose hip_flexor_stretch hamstring_stretch quad_stretch pigeon_stretch figure4_stretch "
           "chest_doorway_stretch lat_stretch cross_body_shoulder_stretch triceps_overhead_stretch neck_side_stretch "
           "neck_flexion_stretch calf_stretch adductor_stretch spinal_twist cobra_stretch forward_fold").split():
    KIND_OF["fc_" + _s] = "stretch"
for _s in "foam_roll_upper_back foam_roll_quad foam_roll_glute foam_roll_it_band foam_roll_calf foam_roll_lats".split():
    KIND_OF["fc_" + _s] = "foam"

# 区域（仅激活 / 动态 / 拉伸 / 泡沫轴需要）
REGION_OF = {
    "fc_superman": "back_core", "fc_bird_dog": "back_core", "fc_clamshell": "hip_glute", "fc_fire_hydrant": "hip_glute",
    "fc_donkey_kick": "hip_glute", "fc_glute_bridge_march": "hip_glute", "fc_frog_pump": "hip_glute",
    "fc_wall_angel": "neck_shoulder", "fc_prone_ytw": "neck_shoulder", "fc_scapular_pushup": "neck_shoulder",
    "fc_chin_tuck": "neck_shoulder", "fc_band_external_rotation": "neck_shoulder", "fc_single_leg_balance": "leg",
    "fc_hip_hinge_drill": "hip_glute", "fc_side_leg_raise": "hip_glute",
    "fc_inchworm": "full", "fc_worlds_greatest_stretch": "full", "fc_leg_swing": "leg", "fc_arm_circle": "neck_shoulder",
    "fc_hip_circle": "hip_glute", "fc_9090_hip": "hip_glute", "fc_ankle_dorsiflexion": "leg",
    "fc_thoracic_rotation": "back_core", "fc_ankle_circle": "leg", "fc_cat_cow": "back_core",
    "fc_childs_pose": "back_core", "fc_hip_flexor_stretch": "hip_glute", "fc_hamstring_stretch": "leg",
    "fc_quad_stretch": "leg", "fc_pigeon_stretch": "hip_glute", "fc_figure4_stretch": "hip_glute",
    "fc_chest_doorway_stretch": "chest_arm", "fc_lat_stretch": "back_core", "fc_cross_body_shoulder_stretch": "neck_shoulder",
    "fc_triceps_overhead_stretch": "chest_arm", "fc_neck_side_stretch": "neck_shoulder", "fc_neck_flexion_stretch": "neck_shoulder",
    "fc_calf_stretch": "leg", "fc_adductor_stretch": "hip_glute", "fc_spinal_twist": "back_core", "fc_cobra_stretch": "back_core",
    "fc_forward_fold": "leg", "fc_foam_roll_upper_back": "back_core", "fc_foam_roll_quad": "leg",
    "fc_foam_roll_glute": "hip_glute", "fc_foam_roll_it_band": "hip_glute", "fc_foam_roll_calf": "leg",
    "fc_foam_roll_lats": "back_core",
}

# 单侧动作（左右各做一次）
PER_SIDE = set("""fc_clamshell fc_fire_hydrant fc_donkey_kick fc_glute_bridge_march fc_bird_dog fc_single_leg_balance
fc_side_leg_raise fc_reverse_lunge fc_bulgarian_split_squat fc_cossack_squat fc_straight_leg_raise fc_band_external_rotation
fc_leg_swing fc_ankle_circle fc_9090_hip fc_ankle_dorsiflexion fc_thoracic_rotation fc_worlds_greatest_stretch
fc_hip_flexor_stretch fc_hamstring_stretch fc_quad_stretch fc_pigeon_stretch fc_figure4_stretch fc_chest_doorway_stretch
fc_lat_stretch fc_cross_body_shoulder_stretch fc_triceps_overhead_stretch fc_neck_side_stretch fc_calf_stretch
fc_spinal_twist fc_foam_roll_quad fc_foam_roll_glute fc_foam_roll_it_band fc_foam_roll_calf fc_foam_roll_lats
fc_side_plank_raise fc_step_up_bw""".split())

# ----------------------------------------------------------------------------- 计量
# 默认「按时间」的动作：静态保持、有氧、拉伸、泡沫轴；其余默认按次数。每个动作都可以在 App 里切换。
TIME_DEFAULT_EXTRA = {
    "fc_wall_sit", "fc_hollow_hold", "fc_dead_hang", "fc_single_leg_balance", "fc_farmer_carry",
}
REPS_DEFAULT_CARDIO = {"fc_burpee", "fc_squat_jump", "fc_jump_squat_lowimpact"}
# 原有 235 个基础动作里需要改默认计量的（slug → tracking）。平板支撑等已经是时间。
BASE_TRACKING_FIX = {"Flutter_Kicks": "duration"}

# ----------------------------------------------------------------------------- 配图
# fc_ 动作 → free-exercise-db 的动作 ID（照片）。没列出的用原创示意图（poses.POSES）。
PHOTO_FOR: dict[str, str] = {
    "fc_treadmill_walk": "Walking_Treadmill", "fc_treadmill_incline_walk": "Walking_Treadmill",
    "fc_treadmill_jog": "Jogging_Treadmill", "fc_treadmill_interval": "Running_Treadmill",
    "fc_stair_climber": "Stairmaster", "fc_rowing_machine": "Rowing_Stationary", "fc_elliptical": "Elliptical_Trainer",
    "fc_stationary_bike": "Bicycling_Stationary", "fc_jump_rope": "Rope_Jumping",
    "fc_outdoor_walk": "Trail_Running_Walking", "fc_outdoor_jog": "Trail_Running_Walking",
    "fc_butt_kicks": "Single_Leg_Butt_Kick", "fc_mountain_climber": "Mountain_Climbers",
    "fc_squat_jump": "Freehand_Jump_Squat", "fc_skater_hop": "Lateral_Bound", "fc_inchworm": "Inchworm",
    "fc_superman": "Superman", "fc_bicycle_crunch": "Air_Bike", "fc_donkey_kick": "Glute_Kickback",
    "fc_fire_hydrant": "Hip_Circles_prone", "fc_step_up_bw": "Step-up_with_Knee_Raise",
    "fc_band_external_rotation": "External_Rotation_with_Band", "fc_side_plank_raise": "Side_Bridge",
    "fc_ankle_circle": "Ankle_Circles", "fc_farmer_carry": "Farmers_Walk", "fc_reverse_lunge": "Crossover_Reverse_Lunge",
    "fc_hip_hinge_drill": "Band_Good_Morning", "fc_kettlebell_swing_two": "One-Arm_Kettlebell_Swings",
    "fc_cat_cow": "Cat_Stretch", "fc_childs_pose": "Childs_Pose", "fc_hip_flexor_stretch": "Kneeling_Hip_Flexor",
    "fc_hamstring_stretch": "Leg-Up_Hamstring_Stretch", "fc_quad_stretch": "Standing_Elevated_Quad_Stretch",
    "fc_figure4_stretch": "Ankle_On_The_Knee", "fc_chest_doorway_stretch": "One_Arm_Against_Wall",
    "fc_lat_stretch": "Side-Lying_Floor_Stretch", "fc_cross_body_shoulder_stretch": "Shoulder_Stretch",
    "fc_triceps_overhead_stretch": "Triceps_Stretch", "fc_neck_side_stretch": "Side_Neck_Stretch",
    "fc_neck_flexion_stretch": "Chin_To_Chest_Stretch", "fc_calf_stretch": "Calf_Stretch_Hands_Against_Wall",
    "fc_adductor_stretch": "Groin_and_Back_Stretch", "fc_spinal_twist": "Knee_Across_The_Body",
    "fc_forward_fold": "Standing_Toe_Touches", "fc_worlds_greatest_stretch": "Worlds_Greatest_Stretch",
    "fc_leg_swing": "Front_Leg_Raises", "fc_arm_circle": "Arm_Circles", "fc_hip_circle": "Standing_Hip_Circles",
    "fc_foam_roll_upper_back": "Rhomboids-SMR", "fc_foam_roll_quad": "Quadriceps-SMR", "fc_foam_roll_glute": "Piriformis-SMR",
    "fc_foam_roll_it_band": "Iliotibial_Tract-SMR", "fc_foam_roll_calf": "Calves-SMR", "fc_foam_roll_lats": "Latissimus_Dorsi-SMR",
}
# 候选动作 key → 已有的 fc_ 动作（两者其实是同一个动作，合并，不重复入库）
DUP_OF = {
    "cat_cow": "fc_cat_cow", "child_pose": "fc_childs_pose", "inchworm": "fc_inchworm", "arm_circles": "fc_arm_circle",
    "standing_hip_circles": "fc_hip_circle", "superman": "fc_superman", "kneel_hip_flexor": "fc_hip_flexor_stretch",
    "lying_hamstring": "fc_hamstring_stretch", "quad_standing": "fc_quad_stretch", "figure4": "fc_figure4_stretch",
    "doorway_chest": "fc_chest_doorway_stretch", "cross_body_shoulder": "fc_cross_body_shoulder_stretch",
    "triceps_overhead": "fc_triceps_overhead_stretch", "neck_side": "fc_neck_side_stretch", "neck_flex": "fc_neck_flexion_stretch",
    "calf_wall": "fc_calf_stretch", "butterfly": "fc_adductor_stretch", "knee_across": "fc_spinal_twist",
    "toe_touch": "fc_forward_fold", "worlds_greatest": "fc_worlds_greatest_stretch", "front_leg_swing": "fc_leg_swing",
    "ankle_circles": "fc_ankle_circle", "foam_quad": "fc_foam_roll_quad", "foam_glute": "fc_foam_roll_glute",
    "foam_itband": "fc_foam_roll_it_band", "foam_calf": "fc_foam_roll_calf", "foam_lat": "fc_foam_roll_lats",
    "foam_upper_back": "fc_foam_roll_upper_back", "band_external_rotation": "fc_band_external_rotation",
    "lying_floor_side": "fc_lat_stretch",
}
# 候选里指向「库内已有动作」的：只补类型 / 区域，不新增（key → 基础动作 slug）
LIB_OF = {
    "glute_bridge": "Butt_Lift_Bridge", "single_leg_bridge": "Single_Leg_Glute_Bridge", "monster_walk": "Monster_Walk",
    "dead_bug": "Dead_Bug", "side_bridge": "Side_Bridge", "band_pull_apart": "Band_Pull_Apart",
}
# 候选里指向「计划库已有的原创动作」（extra:fc_xxx）
# 新增动作的身体部位（激活类要出现在对应的部位分栏里；拉伸/动态/泡沫轴统一 other）
BODY_PART_OF_ACTIVATION = {
    "band_hip_lift": "glutes", "band_hip_extension": "glutes", "band_hip_adduction": "legs", "pelvic_tilt_bridge": "core",
    "band_internal_rotation": "shoulders", "band_back_fly": "shoulders", "scapular_pullup": "back",
    "wall_knee_drive": "legs", "tibialis_raise": "legs",
}
BASE_KIND_OVERRIDE = {  # 基础 235 里属于「激活」的动作：保留原部位，同时出现在「激活」栏
    "Butt_Lift_Bridge": ("activation", "hip_glute"), "Single_Leg_Glute_Bridge": ("activation", "hip_glute"),
    "Monster_Walk": ("activation", "hip_glute"), "Dead_Bug": ("activation", "back_core"),
    "Side_Bridge": ("activation", "back_core"), "Band_Pull_Apart": ("activation", "neck_shoulder"),
    "Glute_Kickback": ("activation", "hip_glute"),
}


def _dose(dose: str, kind: str) -> dict:
    """把「12–15 次 × 2 组」「每侧 30 秒」这类建议量文字拆成数字。"""
    out = {"per_side": bool(re.search(r"每侧|/侧", dose)), "sets": None, "reps": None, "secs": None}
    m = re.search(r"[×x]\s*(\d+)\s*组", dose)
    if m:
        out["sets"] = int(m.group(1))
    m = re.search(r"(\d+)(?:[–-](\d+))?\s*(?:次|步)", dose)
    if m:
        out["reps"] = int(m.group(2) or m.group(1))
    m = re.search(r"(\d+)(?:[–-](\d+))?\s*秒", dose)
    if m:
        out["secs"] = int(m.group(1))
    if kind in ("stretch", "foam") and out["secs"] is None:
        out["secs"] = 30
    if out["sets"] is None:
        out["sets"] = 2 if kind != "foam" else 1
    return out


def uuid_for(slug: str) -> str:
    return str(uuid.uuid5(EXERCISE_NS, slug))


def _fedb() -> dict:
    p = HERE / "cache" / "exercises.json"
    if not p.exists():
        import requests
        p.parent.mkdir(exist_ok=True)
        p.write_bytes(requests.get(
            "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json", timeout=60).content)
    return {x["id"]: x for x in json.loads(p.read_text(encoding="utf-8"))}


def drawn_slugs() -> set[str]:
    from poses import POSES
    return set(POSES)


def finalize(base: list[dict], extras: list[dict]) -> list[dict]:
    """base = 原 235 个；extras = exercises_extra.py 转出的 86 个。返回带新字段的完整列表（base + extras + 新增 wu_）。"""
    fedb = _fedb()
    drawn = drawn_slugs()
    out: list[dict] = []

    def common(e: dict, kind: str, region: str | None, per_side: bool, tracking: str,
               sets: int | None, reps: int | None, secs: int | None, ratio: float) -> dict:
        e = dict(e)
        e.update({"kind": kind, "region": region, "per_side": per_side, "tracking_type": tracking,
                  "default_sets": sets, "default_reps": reps, "default_seconds": secs, "image_ratio": ratio})
        return e

    # 1) 基础 235（被归为「激活」的几个补上区域与建议量）
    lib_dose = {c[7][4:]: _dose(c[6], c[2]) for c in C if c[7].startswith("lib:")}
    for e in base:
        kind, region = BASE_KIND_OVERRIDE.get(e["slug"], ("cardio" if e["body_part"] == "cardio" else "strength", None))
        tracking = BASE_TRACKING_FIX.get(e["slug"], e["tracking_type"])
        d = lib_dose.get(e["slug"], {}) if kind == "activation" else {}
        sets = (d.get("sets") or 2) if kind == "activation" else None
        reps = (d.get("reps") or 12) if kind == "activation" and tracking != "duration" else None
        secs = (d.get("secs") or 30) if kind == "activation" and tracking == "duration" else None
        per_side = bool(d.get("per_side")) or e["slug"] in ("Side_Bridge", "Single_Leg_Glute_Bridge", "Monster_Walk", "Glute_Kickback", "Dead_Bug")
        out.append(common(e, kind, region, per_side, tracking, sets, reps, secs, 1.0))

    # 2) 计划库已有的 86 个：补字段 + 配图
    by_key = {c[0]: c for c in C}
    dose_for: dict[str, dict] = {}
    for key, fc in DUP_OF.items():
        if fc and key in by_key:
            dose_for[fc] = _dose(by_key[key][6], by_key[key][2])
    for c in C:
        if c[7].startswith("extra:"):
            dose_for[c[7][6:]] = _dose(c[6], c[2])
    for e in extras:
        slug = e["slug"]
        kind = KIND_OF.get(slug, "strength")
        region = REGION_OF.get(slug)
        d = dose_for.get(slug, {})
        if kind in ("stretch", "foam"):
            tracking = "duration"
        elif kind == "cardio":
            tracking = "bodyweight_reps" if slug in REPS_DEFAULT_CARDIO else "duration"
        elif slug in TIME_DEFAULT_EXTRA:
            tracking = "duration"
        else:
            tracking = e["tracking_type"] if e["tracking_type"] != "duration" else "duration"
            if kind in ("activation", "dynamic") and tracking == "duration" and slug not in TIME_DEFAULT_EXTRA:
                tracking = "bodyweight_reps"
        per_side = slug in PER_SIDE or d.get("per_side", False)
        sets = d.get("sets") or (2 if kind in ("activation", "dynamic", "stretch") else None)
        reps = d.get("reps") or (10 if kind in ("activation", "dynamic") else None)
        secs = d.get("secs") or (30 if kind in ("stretch",) else (45 if kind == "foam" else None))
        if tracking == "duration" and kind in ("activation", "dynamic") and secs is None:
            secs = 30
        out.append(common(e, kind, region, per_side, tracking, sets, reps, secs, 4 / 3))
        if slug not in PHOTO_FOR and slug not in drawn:
            raise SystemExit(f"{slug} 没有配图来源（既不在 PHOTO_FOR 也没有示意图姿势）")

    # 3) 新增 wu_
    names = {x["name_zh"] for x in out}
    for key, name, kind, region, muscles, cue, dose, src in C:
        if src.startswith(("lib:", "extra:")) or key in DUP_OF or key in LIB_OF:
            continue
        slug = "wu_" + key
        if name in names:
            raise SystemExit(f"动作名重复：{name}")
        names.add(name)
        d = _dose(dose, kind)
        if src.startswith("db:"):
            ref = fedb[src[3:]]
            prim = ref["primaryMuscles"] or []
            sec = ref["secondaryMuscles"] or []
            equip = ref.get("equipment") or "body only"
            en = ref["name"]
        else:
            prim, sec, equip, en = ["calves"] if "tibialis" in key else ["abdominals", "quadriceps"], [], "body only", key.replace("_", " ").title()
        if kind in ("stretch", "foam"):
            tracking, body = "duration", "other"
        elif kind == "dynamic":
            tracking, body = "bodyweight_reps", "other"
        else:
            tracking = "duration" if (d["secs"] and not d["reps"]) else "bodyweight_reps"
            body = BODY_PART_OF_ACTIVATION.get(key) or {"hip_glute": "glutes", "back_core": "core", "neck_shoulder": "shoulders", "leg": "legs",
                                                         "chest_arm": "arms", "full": "other"}[region]
        if equip == "bands" and kind == "activation":
            tracking = tracking
        row = {"id": uuid_for(slug), "slug": slug, "name_zh": name, "name_en": en, "body_part": body,
               "primary_muscles": prim, "secondary_muscles": sec, "equipment": equip, "tracking_type": tracking,
               "instructions_zh": cue,
               "image_paths": [f"{slug}/0.webp", f"{slug}/1.webp"]}
        out.append(common(row, kind, region, d["per_side"], tracking, d["sets"], d["reps"] if tracking != "duration" else None,
                          d["secs"] if tracking == "duration" or kind in ("stretch", "foam") else None, 4 / 3))
        if src.startswith("db:"):
            PHOTO_FOR[slug] = src[3:]
        elif slug not in drawn:
            raise SystemExit(f"{slug} 没有示意图姿势")

    # 4) 基础动作里的「激活」：把候选里的 key 也记到 PHOTO（它们本来就有图，不用处理）
    # 5) 给所有行补 image_paths（extras 之前是空）
    for e in out:
        if not e["image_paths"]:
            e["image_paths"] = [f"{e['slug']}/0.webp", f"{e['slug']}/1.webp"]
    return out
