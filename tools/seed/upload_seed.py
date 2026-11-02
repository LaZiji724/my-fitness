#!/usr/bin/env python3
"""把 build_seed.py 的产物上传到 Supabase（需要 service_role 密钥，只在你自己的电脑上运行）。

  export SUPABASE_URL=https://xxxx.supabase.co
  export SUPABASE_SERVICE_ROLE_KEY=...        # 不要提交到仓库，也不要发给任何人
  ../.venv/bin/python upload_seed.py

可重复运行：动作按 slug 合并更新，图片同名覆盖。
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
from concurrent.futures import ThreadPoolExecutor

import requests

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "out"
BUCKET = "exercise-images"


def main() -> int:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        print("请先设置环境变量 SUPABASE_URL 和 SUPABASE_SERVICE_ROLE_KEY")
        return 1
    rows = json.loads((OUT / "exercises.json").read_text(encoding="utf-8"))
    auth = {"apikey": key, "Authorization": f"Bearer {key}"}

    def upload(path: str) -> None:
        f = OUT / "images" / path
        r = requests.post(
            f"{url}/storage/v1/object/{BUCKET}/{path}",
            headers={**auth, "Content-Type": "image/webp", "x-upsert": "true"},
            data=f.read_bytes(), timeout=60)
        r.raise_for_status()

    paths = sorted({p for r in rows for p in r["image_paths"]})
    print(f"上传 {len(paths)} 张图片…")
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(upload, paths))

    print(f"写入 {len(rows)} 个动作…")
    for i in range(0, len(rows), 100):
        r = requests.post(
            f"{url}/rest/v1/exercises?on_conflict=slug",
            headers={**auth, "Content-Type": "application/json",
                     "Prefer": "resolution=merge-duplicates,return=minimal"},
            data=json.dumps(rows[i:i + 100]), timeout=60)
        if not r.ok:
            print(r.status_code, r.text)
            return 1
    print("完成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
