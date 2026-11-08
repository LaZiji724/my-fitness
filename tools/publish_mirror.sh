#!/usr/bin/env bash
# 把发布好的安装包同步一份到 Supabase 存储（备用下载源），并写好「最新版本信息」。
# App 里的「检查更新」会先看这里；国内连不上 GitHub 时，仍然能从这里查版本、下载安装包。
#
# 用法：tools/publish_mirror.sh <android|ios> <版本号> <tag> <安装包文件> <发版说明文件>
# 需要环境变量：
#   SUPABASE_URL          例如 https://xxxx.supabase.co
#   SUPABASE_SERVICE_KEY  Supabase 的 secret key（sb_secret_...）或旧版 service_role key；没有就跳过（只警告，不算失败）
#   GITHUB_REPOSITORY     例如 LaZiji724/my-fitness
#   MIRRORS               （可选）GitHub 加速代理前缀，空格分隔；不填则 App 用自带的列表
#
# 免费版 Supabase 单个文件最多 50MB，而安装包有 90MB 左右，所以切成每段 40MB 上传，App 下载时按顺序拼起来。
set -euo pipefail

PLATFORM="${1:?缺少平台 android|ios}"
VERSION="${2:?缺少版本号}"
TAG="${3:?缺少 tag}"
FILE="${4:?缺少安装包文件}"
NOTES_FILE="${5:-}"

BUCKET="app-releases"
PART_BYTES=41943040 # 40 MiB

if [ -z "${SUPABASE_SERVICE_KEY:-}" ] || [ -z "${SUPABASE_URL:-}" ]; then
  echo "::warning::没有配置 SUPABASE_SERVICE_KEY，已跳过「备用下载源」同步（App 仍可从 GitHub 更新，只是国内可能连不上）。配置方法见 README「备用下载源」。"
  exit 0
fi
URL="${SUPABASE_URL%/}"
NAME="$(basename "$FILE")"

auth=(-H "apikey: ${SUPABASE_SERVICE_KEY}")
case "$SUPABASE_SERVICE_KEY" in eyJ*) auth+=(-H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}");; esac

api() { curl -sS --fail-with-body --retry 3 --retry-delay 5 --retry-all-errors --max-time 600 "${auth[@]}" "$@"; }

sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
size_of() { wc -c < "$1" | tr -d ' '; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== 准备存储桶 $BUCKET"
code=$(curl -sS -o /dev/null -w '%{http_code}' "${auth[@]}" "$URL/storage/v1/bucket/$BUCKET" || true)
if [ "$code" = "200" ]; then
  api -X PUT -H 'Content-Type: application/json' -d '{"public":true}' "$URL/storage/v1/bucket/$BUCKET" >/dev/null || echo "::warning::没能确认存储桶是公开的"
else
  api -X POST -H 'Content-Type: application/json' \
    -d "{\"id\":\"$BUCKET\",\"name\":\"$BUCKET\",\"public\":true}" "$URL/storage/v1/bucket" >/dev/null
fi

echo "== 切分并上传 $NAME"
SIZE="$(size_of "$FILE")"
SHA="$(sha256_of "$FILE")"
split -b "$PART_BYTES" "$FILE" "$TMP/part."
PARTS_JSON='[]'
i=0
for p in $(ls "$TMP"/part.* | sort); do
  path="$PLATFORM/$VERSION/$NAME.part$i"
  psize="$(size_of "$p")"
  echo "上传 $path（$psize 字节）"
  api -X POST -H 'Content-Type: application/octet-stream' -H 'x-upsert: true' --data-binary @"$p" \
    "$URL/storage/v1/object/$BUCKET/$path" >/dev/null
  # 传完马上用公开地址核对大小，确保 App 以后真的下得到
  got=$(curl -sSI --retry 3 "$URL/storage/v1/object/public/$BUCKET/$path" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)
  if [ "$got" != "$psize" ]; then
    echo "::error::$path 上传后公开地址返回的大小是「$got」，应为 $psize（存储桶没设成公开，或文件超过了存储的单文件上限）"; exit 1
  fi
  PARTS_JSON="$(jq -c --arg path "$path" --argjson size "$psize" '. + [{path:$path,size:$size}]' <<<"$PARTS_JSON")"
  rm -f "$p"
  i=$((i + 1))
done

echo "== 写入最新版本信息 $PLATFORM.json"
NOTES=""
[ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ] && NOTES="$(cat "$NOTES_FILE")"
MIRRORS_JSON="$(printf '%s\n' ${MIRRORS:-} | jq -R . | jq -sc 'map(select(length>0))')"
jq -n \
  --arg version "$VERSION" --arg tag "$TAG" --arg notes "$NOTES" \
  --arg name "$NAME" --argjson size "$SIZE" --arg sha "$SHA" \
  --arg gh "https://github.com/${GITHUB_REPOSITORY:-LaZiji724/my-fitness}/releases/download/$TAG/$NAME" \
  --arg page "https://github.com/${GITHUB_REPOSITORY:-LaZiji724/my-fitness}/releases/tag/$TAG" \
  --argjson parts "$PARTS_JSON" --argjson mirrors "$MIRRORS_JSON" \
  '{version:$version, tag:$tag, notes:$notes, page_url:$page, github_url:$gh,
    asset:{name:$name, size:$size, sha256:$sha}, parts:$parts}
   + (if ($mirrors|length) > 0 then {mirrors:$mirrors} else {} end)
   + {updated_at:(now|todate)}' > "$TMP/manifest.json"
# 信息文件最后上传：它一更新，App 就会开始用新版本，此时分段文件必须已经齐全
api -X POST -H 'Content-Type: application/json' -H 'x-upsert: true' -H 'cache-control: max-age=60' \
  --data-binary @"$TMP/manifest.json" "$URL/storage/v1/object/$BUCKET/$PLATFORM.json" >/dev/null
live=$(curl -sS --retry 3 "$URL/storage/v1/object/public/$BUCKET/$PLATFORM.json?t=$(date +%s)" | jq -r .version)
if [ "$live" != "$VERSION" ]; then
  echo "::error::$PLATFORM.json 上传后读回来的版本是「$live」，应为 $VERSION"; exit 1
fi

echo "== 清理旧版本"
(
  folders=$(api -X POST -H 'Content-Type: application/json' -d "{\"prefix\":\"$PLATFORM\",\"limit\":100}" \
    "$URL/storage/v1/object/list/$BUCKET" | jq -r '.[].name')
  for f in $folders; do
    [ "$f" = "$VERSION" ] && continue
    names=$(api -X POST -H 'Content-Type: application/json' -d "{\"prefix\":\"$PLATFORM/$f\",\"limit\":100}" \
      "$URL/storage/v1/object/list/$BUCKET" | jq -c --arg d "$PLATFORM/$f" '[.[].name | "\($d)/\(.)"]')
    echo "删除旧版本 $PLATFORM/$f：$names"
    api -X DELETE -H 'Content-Type: application/json' -d "{\"prefixes\":$names}" "$URL/storage/v1/object/$BUCKET" >/dev/null
  done
) || echo "::warning::清理旧版本时出了点问题，不影响使用"

echo "完成：备用下载源已同步 $PLATFORM $VERSION（$i 段，共 $SIZE 字节，sha256=$SHA）"
