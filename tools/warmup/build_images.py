"""动作图与计划封面：照片（free-exercise-db，The Unlicense）统一暖黑白处理 + 原创示意图。

动作图 → app/assets/exercises/{slug}_{0,1}.webp（640×480）；新增 / 补图的动作才生成，原有 235 个动作的图不动。
计划封面 → app/assets/programs/{slug}.webp（640×360）。
用法（需要联网下载照片，已下载的缓存在 tools/warmup/cache/photos，不进 git）：
  python3 tools/warmup/build_images.py
"""
from __future__ import annotations

import io
import pathlib
import sys
from concurrent.futures import ThreadPoolExecutor

import requests
from PIL import Image, ImageOps

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

RAW = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"
PHOTOS = HERE / "cache" / "photos"
EX_OUT = ROOT / "app" / "assets" / "exercises"
PROG_OUT = ROOT / "app" / "assets" / "programs"


def tone(gray: Image.Image) -> Image.Image:
    return ImageOps.colorize(gray, black="#1C1A19", mid="#8B8580", white="#F6F3EE")


def photo(dataset_id: str, idx: int) -> Image.Image:
    p = PHOTOS / f"{dataset_id}_{idx}.jpg"
    if not p.exists():
        PHOTOS.mkdir(parents=True, exist_ok=True)
        for attempt in range(3):
            try:
                r = requests.get(f"{RAW}/{dataset_id}/{idx}.jpg", timeout=60)
                r.raise_for_status()
                p.write_bytes(r.content)
                break
            except requests.RequestException:
                if attempt == 2:
                    raise
    return Image.open(p).convert("RGB")


def _subject_cx(gray: Image.Image, thr: int = 80) -> float:
    w, h = gray.size
    small = gray.resize((max(w // 5, 1), max(h // 5, 1)))
    sw, sh = small.size
    px = small.load()
    col = [sum(1 for y in range(int(sh * .05), int(sh * .95)) if px[x, y] < thr) for x in range(sw)]
    tot = sum(col) or 1
    acc, lo, hi = 0, 0, sw - 1
    for x in range(sw):
        acc += col[x]
        if acc < tot * .04:
            lo = x
        if acc < tot * .96:
            hi = x
    return (lo + hi + 1) / 2 * 5


def crop_ratio(img: Image.Image, ratio: float, out: tuple[int, int]) -> Image.Image:
    """按人物位置水平居中裁成 ratio（宽/高），灰度 + 自动对比 + 暖调三色映射。"""
    w, h = img.size
    gray = ImageOps.autocontrast(ImageOps.grayscale(img), cutoff=1)
    cw = min(w, int(h * ratio))
    ch = int(cw / ratio) if cw / ratio <= h else h
    cx = _subject_cx(gray)
    left = int(min(max(cx - cw / 2, 0), w - cw))
    top = int(min(max((h - ch) * 0.35, 0), h - ch))
    return tone(gray.crop((left, top, left + cw, top + ch))).resize(out, Image.LANCZOS)


def save_webp(im: Image.Image, path: pathlib.Path, q: int = 78) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "WEBP", quality=q, method=6)


def build_exercise_images(exercises: list[dict], base_count: int) -> dict[str, str]:
    """返回 slug → 图片来源（photo:ID / drawn），并写文件。"""
    from catalog import PHOTO_FOR
    from figure import render
    from poses import POSES
    src: dict[str, str] = {}
    jobs = []
    for e in exercises[base_count:]:
        slug = e["slug"]
        if slug in PHOTO_FOR:
            src[slug] = "photo:" + PHOTO_FOR[slug]
            jobs.append((slug, PHOTO_FOR[slug]))
        elif slug in POSES:
            src[slug] = "drawn"
        else:
            raise SystemExit(f"{slug} 没有图")

    def one(job):
        slug, did = job
        for i in (0, 1):
            save_webp(crop_ratio(photo(did, i), 4 / 3, (640, 480)), EX_OUT / f"{slug}_{i}.webp")

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(one, jobs))
    for slug, (a, b) in POSES.items():
        if src.get(slug) == "drawn":
            save_webp(render(a), EX_OUT / f"{slug}_0.webp", 82)
            save_webp(render(b), EX_OUT / f"{slug}_1.webp", 82)
    return src


def build_program_covers(programs: list[dict], exercises: list[dict]) -> dict[str, str]:
    """每个计划一张健身房照片作封面：优先用计划里有照片的动作，同一张尽量不重复。"""
    from catalog import PHOTO_FOR
    by_id = {e["id"]: e for e in exercises}

    def dataset_id(e: dict) -> str | None:
        return PHOTO_FOR.get(e["slug"]) or (e["slug"] if not e["slug"].startswith(("fc_", "wu_")) else None)

    used: set[tuple[str, int]] = set()
    chosen: dict[str, tuple[str, int]] = {}
    for p in programs:
        cands: list[str] = []
        for s in p["sessions"]:
            for it in s["items"]:
                if it.get("section", "main") != "main":
                    continue
                did = dataset_id(by_id[it["exercise_id"]])
                if did and did not in cands:
                    cands.append(did)
        if not cands:  # 全是示意图动作的计划：退而求其次，用任意有照片的动作
            for s in p["sessions"]:
                for it in s["items"]:
                    did = dataset_id(by_id[it["exercise_id"]])
                    if did and did not in cands:
                        cands.append(did)
        pick = next(((d, i) for d in cands for i in (0, 1) if (d, i) not in used), None)
        pick = pick or (cands[0], 0) if cands else None
        if pick is None:
            raise SystemExit(f"计划 {p['slug']} 找不到可用于封面的照片")
        used.add(pick)
        chosen[p["slug"]] = pick

    def one(item):
        slug, (did, idx) = item
        save_webp(crop_ratio(photo(did, idx), 16 / 9, (640, 360)), PROG_OUT / f"{slug}.webp", 74)

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(one, chosen.items()))
    return {k: f"{v[0]}_{v[1]}" for k, v in chosen.items()}


def main() -> None:
    sys.path.insert(0, str(ROOT / "tools" / "programs"))
    import build_programs
    exercises, programs = build_programs.build()
    src = build_exercise_images(exercises, build_programs.BASE_COUNT)
    covers = build_program_covers(programs, exercises)
    drawn = sum(1 for v in src.values() if v == "drawn")
    print(f"动作图：照片 {len(src) - drawn}，原创示意图 {drawn}；计划封面 {len(covers)}")


if __name__ == "__main__":
    main()
