#!/usr/bin/env python3
"""动作库种子构建：free-exercise-db（The Unlicense，公有领域） + 手工精选中文名。

读取 curated.txt（英文名 => 中文名），生成：
  out/exercises.json   可直接 upsert 到 Supabase exercises 表的行（owner_id 为空 = 内置动作）
  out/images/{slug}/0.webp、1.webp   压缩后的动作图（长边 480px）
  out/report.txt       数量与体积汇总

用法：
  python3 -m venv ../.venv && ../.venv/bin/pip install pillow requests
  ../.venv/bin/python build_seed.py
"""
from __future__ import annotations

import io
import json
import pathlib
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor

import requests
from PIL import Image

from instructions_zh import INSTRUCTIONS_ZH

HERE = pathlib.Path(__file__).resolve().parent
CACHE = HERE / "cache"
OUT = HERE / "out"
RAW = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main"
NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "https://my-fitness.local/exercise")

BODY_PART = {
    "chest": "chest",
    "lats": "back", "middle back": "back", "lower back": "back", "traps": "back",
    "shoulders": "shoulders",
    "biceps": "arms", "triceps": "arms", "forearms": "arms",
    "quadriceps": "legs", "hamstrings": "legs", "calves": "legs",
    "adductors": "legs", "abductors": "legs",
    "glutes": "glutes",
    "abdominals": "core",
    "neck": "other",
}
# 数据集里主要肌群标注不理想的动作，手工指定部位
BODY_PART_OVERRIDE = {
    "Barbell Deadlift": "back",
    "Romanian Deadlift": "legs",
    "Sumo Deadlift": "legs",
    "Stiff-Legged Barbell Deadlift": "legs",
    "Rack Pulls": "back",
    "Good Morning": "legs",
    "Glute Ham Raise": "legs",
    "Pull Through": "glutes",
}
# 自重动作按“次数”记录，不填重量（器械类用 weight_reps）
BODYWEIGHT_EQUIPMENT = {"body only"}


def fetch_json(url: str, dest: pathlib.Path):
    if not dest.exists():
        CACHE.mkdir(exist_ok=True)
        print("下载", url)
        r = requests.get(url, timeout=60)
        r.raise_for_status()
        dest.write_bytes(r.content)
    return json.loads(dest.read_text(encoding="utf-8"))


def parse_curated() -> list[tuple[str, str, str | None]]:
    rows = []
    for line in (HERE / "curated.txt").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        en, rest = line.split(" => ", 1)
        override = None
        if " |" in rest:
            rest, override = rest.rsplit(" |", 1)
            override = override.strip()
        rows.append((en.strip(), rest.strip(), override))
    return rows


# 动作图处理：居中裁成正方形 → 480×480，保留照片原有色彩。
# （最早的版本做过灰度 + 暖调三色映射，用户希望看到真实的颜色，所以去掉了。）
def stylize(img: Image.Image) -> Image.Image:
    img = img.convert("RGB")
    w, h = img.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    return img.resize((480, 480), Image.LANCZOS)


def convert_image(slug: str, idx: int) -> int:
    dest = OUT / "images" / slug / f"{idx}.webp"
    if dest.exists():
        return dest.stat().st_size
    url = f"{RAW}/exercises/{slug}/{idx}.jpg"
    for attempt in range(3):
        try:
            r = requests.get(url, timeout=60)
            r.raise_for_status()
            break
        except requests.RequestException:
            if attempt == 2:
                raise
    img = stylize(Image.open(io.BytesIO(r.content)))
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, "WEBP", quality=80, method=6)
    return dest.stat().st_size


def main() -> int:
    data = fetch_json(f"{RAW}/dist/exercises.json", CACHE / "exercises.json")
    by_name = {x["name"]: x for x in data}
    curated = parse_curated()

    rows, missing = [], []
    for en, zh, override in curated:
        src = by_name.get(en)
        if src is None:
            missing.append(en)
            continue
        primary = src["primaryMuscles"] or []
        part = BODY_PART_OVERRIDE.get(en) or (BODY_PART.get(primary[0], "other") if primary else "other")
        if override in {"duration", "weight_reps", "bodyweight_reps"}:
            tracking = override
        elif src.get("equipment") in BODYWEIGHT_EQUIPMENT:
            tracking = "bodyweight_reps"
        else:
            tracking = "weight_reps"
        slug = src["id"]
        rows.append({
            "id": str(uuid.uuid5(NAMESPACE, slug)),
            "slug": slug,
            "name_zh": zh,
            "name_en": en,
            "body_part": part,
            "primary_muscles": primary,
            "secondary_muscles": src["secondaryMuscles"] or [],
            "equipment": src.get("equipment"),
            "tracking_type": tracking,
            "instructions_zh": INSTRUCTIONS_ZH.get(slug),
            "image_paths": [f"{slug}/{i}.webp" for i in range(len(src["images"]))],
        })
    if missing:
        print("以下英文名在数据集中找不到，请检查 curated.txt：", *missing, sep="\n  ")
        return 1

    OUT.mkdir(exist_ok=True)
    jobs = [(r["slug"], i) for r in rows for i in range(len(r["image_paths"]))]
    with ThreadPoolExecutor(max_workers=8) as pool:
        sizes = list(pool.map(lambda j: convert_image(*j), jobs))

    (OUT / "exercises.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    by_part: dict[str, int] = {}
    for r in rows:
        by_part[r["body_part"]] = by_part.get(r["body_part"], 0) + 1
    report = [
        f"动作数量：{len(rows)}",
        f"图片数量：{len(jobs)}，总大小 {sum(sizes) / 1024 / 1024:.1f} MB，平均 {sum(sizes) / len(sizes) / 1024:.0f} KB",
        "部位分布：" + "，".join(f"{k} {v}" for k, v in sorted(by_part.items())),
    ]
    (OUT / "report.txt").write_text("\n".join(report), encoding="utf-8")
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
