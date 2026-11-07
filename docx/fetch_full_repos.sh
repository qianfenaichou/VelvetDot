#!/bin/bash
# 可选：下载完整版香山学习/文档仓库（含图片、波形等大文件）
# 用法：bash fetch_full_repos.sh
# 注意：XiangShanLab 约 951MB、XiangShan-doc 约 476MB（GitHub 标注），网络差时可能较慢。

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPOS="$(cd "$HERE/../repos" && pwd)"
cd "$REPOS"

if [ ! -d XiangShanLab-full ]; then
  echo ">>> 克隆 XiangShanLab（完整版）"
  git clone --depth 1 https://github.com/OpenXiangShan/XiangShanLab.git XiangShanLab-full
else
  echo "XiangShanLab-full 已存在，跳过"
fi

if [ ! -d XiangShan-doc-full ]; then
  echo ">>> 克隆 XiangShan-doc（完整版）"
  git clone --depth 1 https://github.com/OpenXiangShan/XiangShan-doc.git XiangShan-doc-full
else
  echo "XiangShan-doc-full 已存在，跳过"
fi

echo ">>> 完成。"
