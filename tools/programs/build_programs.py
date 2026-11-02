#!/usr/bin/env python3
"""计划库构建：校验内容 → 生成
  app/assets/seed/programs.json        随包种子（离线可用）
  app/assets/seed/exercises.json       追加新增的原创动作（已有动作不动）
  supabase/seed/program_library.sql    可重复执行的 SQL（动作 + 计划 + 课次 + 动作链）

用法：python3 tools/programs/build_programs.py
"""
from __future__ import annotations

import json
import pathlib
import sys
import uuid

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

from lib import (parse_items, AUDIENCES, EQUIP_ZH, EXERCISE_NS, GOAL_CATEGORIES, ITEM_NS, LEVELS, PROGRAM_NS, SCENES,  # noqa: E402
                 SESSION_NS, session_minutes)
from exercises_extra import EXTRA  # noqa: E402
import content_cardio, content_fat_shape, content_muscle, content_health, content_glute, content_activation  # noqa: E402

sys.path.insert(0, str(HERE.parent / "warmup"))
import catalog  # noqa: E402

SEED = ROOT / "app" / "assets" / "seed"
BASE_EXERCISES = SEED / "exercises.json"
BASE_COUNT = 235  # 随包基础动作数；之后的都是本脚本追加的原创动作


# 没有「热身 / 放松」区的课次，按课次主要练的部位补一段徒手的默认热身与放松（不需要任何器械）
DEFAULT_WARMUP = {
    "lower": "站姿摆腿@1x10 r0 #前后各摆动，幅度由小渐大；髋部绕环@1x10 r0 #每个方向各一圈；臀桥@1x12 r0 #顶点夹臀停 1 秒",
    "push": "手臂绕环@1x12 r0 #由小到大；肩部绕环@1x10 r0；肩胛俯卧撑@1x10 r0 #手臂伸直，只动肩胛",
    "pull": "猫牛式@1x10 r0 #配合呼吸；手臂绕环@1x12 r0 #由小到大；靠墙天使@1x10 r0 #背贴墙，手臂沿墙滑动",
    "core": "猫牛式@1x10 r0 #配合呼吸；死虫式@1x8 r0 #每侧各 8；鸟狗式@1x8 r0 #每侧各 8",
    "full": "手臂绕环@1x12 r0 #由小到大；髋部绕环@1x10 r0 #每个方向各一圈；尺蠖爬行@1x6 r0",
}
DEFAULT_COOLDOWN = {
    "lower": "站姿股四头肌拉伸@1x30s r0 #每侧各一次；仰卧腘绳肌拉伸@1x30s r0 #每侧各一次；仰卧 4 字拉伸@1x30s r0 #每侧各一次",
    "push": "门框胸部拉伸@1x30s r0 #每侧各一次；肩后侧交叉拉伸@1x30s r0 #每侧各一次；过头三头肌拉伸@1x30s r0 #每侧各一次",
    "pull": "跪姿背阔肌拉伸@1x30s r0 #每侧各一次；婴儿式@1x40s r0；肩后侧交叉拉伸@1x30s r0 #每侧各一次",
    "core": "眼镜蛇式@1x30s r0；婴儿式@1x40s r0；仰卧脊柱扭转@1x30s r0 #每侧各一次",
    "full": "婴儿式@1x40s r0；站姿体前屈@1x30s r0 #膝盖微屈；门框胸部拉伸@1x30s r0 #每侧各一次",
}
NO_SECTION_CATEGORIES = {"激活热身", "拉伸放松"}


def load_exercises() -> list[dict]:
    base = json.loads(BASE_EXERCISES.read_text(encoding="utf-8"))[:BASE_COUNT]
    assert len(base) == BASE_COUNT, "基础动作数量不对"
    extra = []
    for slug, zh, en, body, prim, sec, equip, tracking, instr in EXTRA:
        extra.append({
            "id": str(uuid.uuid5(EXERCISE_NS, slug)), "slug": slug, "name_zh": zh, "name_en": en,
            "body_part": body, "primary_muscles": prim, "secondary_muscles": sec, "equipment": equip,
            "tracking_type": tracking, "instructions_zh": instr, "image_paths": [],
        })
    return catalog.finalize(base, extra)


def classify(items, by_name):
    """给一个课次的条目分区：开头的热身类 → warmup，结尾的拉伸类 → cooldown，其余 → main。"""
    n = len(items)

    def is_warm(it):
        ex = by_name.get(it.name)
        # 有氧器械的「热身」条目：备注以「热身」开头（力量动作备注里的「热身组」不算）
        cardio_warm = ex is not None and ex["kind"] == "cardio" and bool(it.note and it.note.startswith("热身"))
        return cardio_warm or (ex is not None and ex["kind"] in ("dynamic", "activation"))

    def is_cool(it):
        ex = by_name.get(it.name)
        cardio_cool = ex is not None and ex["kind"] == "cardio" and bool(it.note and it.note.startswith("放松"))
        return cardio_cool or (ex is not None and ex["kind"] in ("stretch", "foam"))

    a = 0
    while a < n - 1 and is_warm(items[a]):
        a += 1
    b = n
    while b > a + 1 and is_cool(items[b - 1]):
        b -= 1
    for i, it in enumerate(items):
        it.section = "warmup" if i < a else ("cooldown" if i >= b else "main")


def profile(items, by_name) -> str:
    cnt = {"lower": 0, "push": 0, "pull": 0, "core": 0, "cardio": 0}
    for it in items:
        if it.section != "main":
            continue
        ex = by_name[it.name]
        bp = ex["body_part"]
        if bp in ("legs", "glutes"):
            cnt["lower"] += 1
        elif bp in ("chest", "shoulders"):
            cnt["push"] += 1
        elif bp in ("back",):
            cnt["pull"] += 1
        elif bp == "arms":
            cnt["push" if "triceps" in ex["primary_muscles"] else "pull"] += 1
        elif bp == "core":
            cnt["core"] += 1
        elif bp == "cardio":
            cnt["cardio"] += 1
    total = sum(cnt.values())
    if total == 0:
        return "full"
    top = max(cnt, key=cnt.get)
    if cnt[top] / total < 0.6:
        return "full"
    return "lower" if top == "cardio" else top


def build() -> tuple[list[dict], list[dict]]:
    exercises = load_exercises()
    by_name = {e["name_zh"]: e for e in exercises}
    assert len(by_name) == len(exercises), "动作中文名有重复"
    plans = (content_cardio.PLANS + content_fat_shape.PLANS + content_muscle.PLANS
             + content_health.PLANS + content_glute.PLANS + content_activation.PLANS)
    errors: list[str] = []
    programs: list[dict] = []
    slugs: set[str] = set()
    for order, p in enumerate(plans):
        tag = f"[{p.slug}]"
        if p.slug in slugs:
            errors.append(f"{tag} slug 重复")
        slugs.add(p.slug)
        if p.category not in GOAL_CATEGORIES:
            errors.append(f"{tag} 分类无效 {p.category}")
        if p.level not in LEVELS:
            errors.append(f"{tag} 难度无效 {p.level}")
        if len(p.schedule) != 7:
            errors.append(f"{tag} schedule 不是 7 位: {p.schedule!r}")
        keys = [s.key for s in p.sessions]
        if len(set(keys)) != len(keys):
            errors.append(f"{tag} 课次 key 重复")
        for ch in p.schedule:
            if ch != "." and ch not in keys:
                errors.append(f"{tag} schedule 引用了不存在的课次 {ch}")
        for k in keys:
            if k not in p.schedule:
                errors.append(f"{tag} 课次 {k} 没被排进 schedule")
        for sc in p.scenes:
            if sc not in SCENES:
                errors.append(f"{tag} 场景无效 {sc}")
        for au in p.audiences:
            if au not in AUDIENCES:
                errors.append(f"{tag} 人群无效 {au}")
        if not (20 <= len(p.description) <= 220):
            errors.append(f"{tag} 描述长度 {len(p.description)}")
        equip_order: list[str] = []
        sessions_out = []
        for sp, s in enumerate(p.sessions):
            items_out = []
            if p.category in NO_SECTION_CATEGORIES:
                for it in s.items:
                    it.section = "main"
            else:
                classify(s.items, by_name)
                prof = profile(s.items, by_name)
                if not any(it.section == "warmup" for it in s.items):
                    extra_warm = parse_items(DEFAULT_WARMUP[prof])
                    for it in extra_warm:
                        it.section = "warmup"
                    s.items = extra_warm + s.items
                if not any(it.section == "cooldown" for it in s.items):
                    extra_cool = parse_items(DEFAULT_COOLDOWN[prof])
                    for it in extra_cool:
                        it.section = "cooldown"
                    s.items = s.items + extra_cool
            for ip, it in enumerate(s.items):
                ex = by_name.get(it.name)
                if ex is None:
                    errors.append(f"{tag} {s.key}: 找不到动作「{it.name}」")
                    continue
                tt = ex["tracking_type"]
                if it.duration_sec is not None and tt != "duration":
                    errors.append(f"{tag} {s.key}: 「{it.name}」是 {tt}，不能用时长目标")
                if it.duration_sec is None and tt == "duration":
                    errors.append(f"{tag} {s.key}: 「{it.name}」是时长动作，需要用 s/m 目标")
                if it.warmup_sets and tt != "weight_reps":
                    errors.append(f"{tag} {s.key}: 「{it.name}」不是重量动作，不该有热身组")
                eq = ex["equipment"] or "other"
                if eq != "body only" and eq not in equip_order:
                    equip_order.append(eq)
                items_out.append({
                    "id": str(uuid.uuid5(ITEM_NS, f"{p.slug}/{s.key}/{ip}")),
                    "exercise_id": ex["id"], "exercise_slug": ex["slug"], "position": ip,
                    "warmup_sets": it.warmup_sets, "sets": it.sets,
                    "reps_min": it.reps_min, "reps_max": it.reps_max,
                    "duration_sec": it.duration_sec, "distance_m": it.distance_m,
                    "rest_sec": it.rest_sec, "note": it.note, "section": it.section,
                })
            sessions_out.append({
                "id": str(uuid.uuid5(SESSION_NS, f"{p.slug}/{s.key}")), "key": s.key, "name": s.name,
                "focus": s.focus, "position": sp, "minutes": session_minutes(s.items), "items": items_out,
            })
        days = sum(1 for ch in p.schedule if ch != ".")
        minutes = round(sum(next(x for x in sessions_out if x["key"] == ch)["minutes"]
                            for ch in p.schedule if ch != ".") / max(days, 1) / 5) * 5
        programs.append({
            "id": str(uuid.uuid5(PROGRAM_NS, p.slug)), "slug": p.slug, "name": p.name,
            "subtitle": p.subtitle, "description": p.description, "progression": p.progression,
            "category": p.category, "level": LEVELS[p.level], "weeks": p.weeks,
            "days_per_week": days, "minutes": minutes, "schedule": p.schedule,
            "scenes": p.scenes, "audiences": p.audiences,
            "equipment": [EQUIP_ZH.get(e, e) for e in equip_order] or ["徒手"],
            "is_new": p.is_new, "featured": p.featured, "sort_order": order, "sessions": sessions_out,
        })
    if errors:
        print("\n".join(errors))
        raise SystemExit(f"共 {len(errors)} 个问题")
    return exercises, programs


def sql_str(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "array[" + ",".join(sql_str(x) for x in v) + "]::text[]" if v else "'{}'::text[]"
    return "'" + str(v).replace("'", "''") + "'"


def write_sql(exercises: list[dict], programs: list[dict], out: pathlib.Path) -> None:
    L: list[str] = [
        "-- 我的健身 · 内置计划库种子（由 tools/programs/build_programs.py 生成，可重复执行）",
        "-- 先执行 supabase/migrations/20261103000000_program_library.sql 与 20261104000000_warmup_stretch.sql，再在 SQL Editor 里执行本文件。",
        "begin;",
    ]
    # 原有 235 个基础动作：只补类型 / 区域 / 默认计量（图片和文字都不动）
    for e in exercises[:BASE_COUNT]:
        if e["kind"] == "strength" and e["slug"] not in catalog.BASE_TRACKING_FIX:
            continue
        L.append("update public.exercises set kind = {k}, region = {r}, tracking_type = {t} where slug = {s};".format(
            k=sql_str(e["kind"]), r=sql_str(e["region"]), t=sql_str(e["tracking_type"]), s=sql_str(e["slug"])))
    for e in exercises[BASE_COUNT:]:
        L.append(
            "insert into public.exercises (id, owner_id, slug, name_zh, name_en, body_part, primary_muscles, "
            "secondary_muscles, equipment, tracking_type, instructions_zh, image_paths, kind, region, per_side, "
            "default_sets, default_reps, default_seconds) values ("
            f"{sql_str(e['id'])}, null, {sql_str(e['slug'])}, {sql_str(e['name_zh'])}, {sql_str(e['name_en'])}, "
            f"{sql_str(e['body_part'])}, {sql_str(e['primary_muscles'])}, {sql_str(e['secondary_muscles'])}, "
            f"{sql_str(e['equipment'])}, {sql_str(e['tracking_type'])}, {sql_str(e['instructions_zh'])}, "
            f"{sql_str(e['image_paths'])}, {sql_str(e['kind'])}, {sql_str(e['region'])}, {sql_str(e['per_side'])}, "
            f"{sql_str(e['default_sets'])}, {sql_str(e['default_reps'])}, {sql_str(e['default_seconds'])}) "
            "on conflict (slug) do update set name_zh = excluded.name_zh, name_en = excluded.name_en, "
            "body_part = excluded.body_part, primary_muscles = excluded.primary_muscles, "
            "secondary_muscles = excluded.secondary_muscles, equipment = excluded.equipment, "
            "tracking_type = excluded.tracking_type, instructions_zh = excluded.instructions_zh, "
            "image_paths = excluded.image_paths, kind = excluded.kind, region = excluded.region, "
            "per_side = excluded.per_side, default_sets = excluded.default_sets, "
            "default_reps = excluded.default_reps, default_seconds = excluded.default_seconds;")
    # 计划整体重建：先删后插（子表级联删除），保证改内容后重复执行结果一致
    ids = ",".join(sql_str(p["id"]) for p in programs)
    L.append(f"delete from public.programs where id in ({ids});")
    for p in programs:
        L.append(
            "insert into public.programs (id, slug, name, subtitle, description, progression, category, level, weeks, "
            "days_per_week, minutes, schedule, scenes, audiences, equipment, is_new, featured, sort_order) values ("
            f"{sql_str(p['id'])}, {sql_str(p['slug'])}, {sql_str(p['name'])}, {sql_str(p['subtitle'])}, "
            f"{sql_str(p['description'])}, {sql_str(p['progression'])}, {sql_str(p['category'])}, {p['level']}, "
            f"{p['weeks']}, {p['days_per_week']}, {p['minutes']}, {sql_str(p['schedule'])}, {sql_str(p['scenes'])}, "
            f"{sql_str(p['audiences'])}, {sql_str(p['equipment'])}, {sql_str(p['is_new'])}, {sql_str(p['featured'])}, "
            f"{p['sort_order']});")
        for s in p["sessions"]:
            L.append(
                "insert into public.program_sessions (id, program_id, key, name, focus, minutes, position) values ("
                f"{sql_str(s['id'])}, {sql_str(p['id'])}, {sql_str(s['key'])}, {sql_str(s['name'])}, "
                f"{sql_str(s['focus'])}, {s['minutes']}, {s['position']});")
            rows = []
            for it in s["items"]:
                rows.append(
                    f"({sql_str(it['id'])}, {sql_str(s['id'])}, {sql_str(it['exercise_id'])}, {it['position']}, "
                    f"{it['warmup_sets']}, {it['sets']}, {sql_str(it['reps_min'])}, {sql_str(it['reps_max'])}, "
                    f"{sql_str(it['duration_sec'])}, {sql_str(it['distance_m'])}, {it['rest_sec']}, {sql_str(it['note'])}, {sql_str(it['section'])})")
            L.append("insert into public.program_session_items (id, session_id, exercise_id, position, warmup_sets, "
                     "sets, reps_min, reps_max, duration_sec, distance_m, rest_sec, note, section) values\n  "
                     + ",\n  ".join(rows) + ";")
    L.append("commit;")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(L) + "\n", encoding="utf-8")


def main() -> None:
    exercises, programs = build()
    BASE_EXERCISES.write_text(json.dumps(exercises, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    # 程序 JSON 不带 exercise_slug 以外的冗余：App 里用 exercise_id 对应动作库
    (SEED / "programs.json").write_text(json.dumps(programs, ensure_ascii=False, separators=(",", ":")) + "\n",
                                        encoding="utf-8")
    write_sql(exercises, programs, ROOT / "supabase" / "seed" / "program_library.sql")
    items = sum(len(s["items"]) for p in programs for s in p["sessions"])
    sessions = sum(len(p["sessions"]) for p in programs)
    print(f"动作 {len(exercises)}（新增 {len(exercises) - BASE_COUNT}），计划 {len(programs)}，课次 {sessions}，动作条目 {items}")
    from collections import Counter
    print(Counter(p["category"] for p in programs))
    print(Counter(p["level"] for p in programs))


if __name__ == "__main__":
    main()
