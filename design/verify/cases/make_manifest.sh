#!/usr/bin/env bash
# 把 manifest.tsv 里的 @IMG_DIR@ 换成绝对路径，输出到 stdout。
# 未给出 IMG_DIR 时默认用 /public/home/$USER/core/test/bin；USER 为空则直接报错，不产出半成品清单。
# 用法：IMG_DIR=/public/home/USER/core/test/bin bash design/verify/cases/make_manifest.sh > /path/manifest.tsv
#   或   bash make_manifest.sh [IMG_DIR] [MANIFEST源]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IMG_DIR="${1:-${IMG_DIR:-/public/home/${USER:?需要 IMG_DIR 参数或非空 USER}/core}/test/bin}"
SRC="${2:-$HERE/manifest.tsv}"
[ -f "$SRC" ] || { echo "[FATAL] 缺 manifest 源 $SRC" >&2; exit 3; }
sed "s|@IMG_DIR@|$IMG_DIR|g" "$SRC"
