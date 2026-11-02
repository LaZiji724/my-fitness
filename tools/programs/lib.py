"""计划库内容的小型 DSL：解析、校验、生成 JSON 与 SQL。

一个动作条目：  名称@组数x次数 [rN 休息秒] [wN 热身组数] [#要点]
  杠铃卧推@4x6-8 r120 w2 #最后一组留 1–2 次余力
  平板支撑@3x40s r30        （s=秒，m=分钟 → 时长目标）
  跑步机快走@1x20m d2km #速度 5.5      （d= 距离目标：d2km / d500m）
条目之间用 ; 或 ； 或换行分隔（备注里不要出现这些符号）。
"""
from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass, field

LEVELS = {"初阶": 1, "中阶": 2, "高阶": 3}
CATEGORIES = ["新手入门", "进阶计划", "有氧跟练", "团课计划", "瘦身减脂", "塑形美体", "增肌增重", "健康改善", "拉伸放松", "丰满翘臀"]
# 「新手入门」「进阶计划」不单独存：初阶=新手入门，中/高阶=进阶计划，由 App 推导。
GOAL_CATEGORIES = ["有氧跟练", "团课计划", "瘦身减脂", "塑形美体", "增肌增重", "健康改善", "拉伸放松", "丰满翘臀"]
SCENES = ["健身房", "居家", "户外"]
AUDIENCES = ["新手", "久坐上班族", "女性", "男性", "有基础者", "中老年"]

EQUIP_ZH = {
    "barbell": "杠铃", "e-z curl bar": "EZ 杠", "dumbbell": "哑铃", "machine": "固定器械", "cable": "绳索",
    "kettlebells": "壶铃", "bands": "弹力带", "treadmill": "跑步机", "stair climber": "爬楼机", "rower": "划船机",
    "elliptical": "椭圆机", "bike": "固定自行车", "jump rope": "跳绳", "foam roll": "泡沫轴", "other": "凳子/单杠",
    "body only": "徒手",
}

PROGRAM_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://my-fitness.local/program")
SESSION_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://my-fitness.local/program-session")
ITEM_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://my-fitness.local/program-item")
EXERCISE_NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://my-fitness.local/exercise")

_ITEM = re.compile(r"^(?P<name>[^@]+)@(?P<sets>\d+)x(?P<target>\d+(?:-\d+)?[sm]?)(?P<rest>(?:\s+(?:r\d+|w\d+|d\d+(?:km|m)))*)\s*(?:#(?P<note>.*))?$")


@dataclass
class Item:
    name: str
    sets: int
    reps_min: int | None
    reps_max: int | None
    duration_sec: int | None
    rest_sec: int
    warmup_sets: int = 0
    distance_m: int | None = None
    note: str | None = None


def parse_items(text: str) -> list[Item]:
    out: list[Item] = []
    for raw in re.split(r"[;；\n]", text):
        raw = raw.strip()
        if not raw:
            continue
        m = _ITEM.match(raw)
        if not m:
            raise ValueError(f"无法解析动作条目: {raw!r}")
        target = m["target"]
        reps_min = reps_max = duration = None
        if target.endswith("s"):
            duration = int(target[:-1])
        elif target.endswith("m"):
            duration = int(target[:-1]) * 60
        else:
            a, _, b = target.partition("-")
            reps_min = int(a)
            reps_max = int(b or a)
        rest = 60
        warm = 0
        dist = None
        for tok in m["rest"].split():
            if tok[0] == "r":
                rest = int(tok[1:])
            elif tok[0] == "w":
                warm = int(tok[1:])
            elif tok[0] == "d":
                dist = int(tok[1:-2]) * 1000 if tok.endswith("km") else int(tok[1:-1])
        out.append(Item(m["name"].strip(), int(m["sets"]), reps_min, reps_max, duration, rest, warm, dist,
                        (m["note"] or "").strip() or None))
    return out


@dataclass
class Session:
    key: str
    name: str
    focus: str
    items: list[Item]


@dataclass
class Program:
    slug: str
    name: str
    category: str
    level: str
    weeks: int
    schedule: str  # 7 个字符，session.key 或 '.'（休息）
    scenes: list[str]
    audiences: list[str]
    subtitle: str
    description: str
    progression: str
    sessions: list[Session]
    is_new: bool = False
    featured: bool = False


def S(key: str, name: str, focus: str, items: str) -> Session:
    return Session(key, name, focus, parse_items(items))


def P(slug, name, category, level, weeks, schedule, scenes, audiences, subtitle, description, progression,
      sessions, is_new=False, featured=False) -> Program:
    return Program(slug, name, category, level, weeks, schedule, scenes, audiences, subtitle, description,
                   progression, sessions, is_new, featured)


def session_minutes(items: list[Item]) -> int:
    sec = 0
    for it in items:
        work = it.duration_sec if it.duration_sec else ((it.reps_min or 0) + (it.reps_max or 0)) / 2 * 4
        sec += it.warmup_sets * (30 + 45) + it.sets * work + max(0, it.sets - 1) * it.rest_sec + 40  # 换动作缓冲
    return max(5, int(round(sec / 60 / 5.0)) * 5) if sec > 0 else 5
