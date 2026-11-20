#!/bin/zsh
# 让 Codex 只读地看一个仓库并回答一份任务说明；答案写到文件。调查员和评审意见都走这里。
# 用法: codex.sh <仓库路径> <任务说明文件> <答案输出文件>
set -eu
repo=${1:?用法: codex.sh <仓库> <任务说明文件> <输出文件>}; brief=${2:?}; out=${3:?}
mkdir -p "$(dirname "$out")"
# -s read-only: Codex 不能改仓库。它的答案是意见，不是指令。
codex exec -s read-only --skip-git-repo-check -C "$repo" -o "$out" - < "$brief" > "${out%.*}.log" 2>&1
