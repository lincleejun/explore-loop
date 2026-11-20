#!/bin/bash
# 端到端自检：在临时目录建一个玩具仓库，把 init → doctor → aa → land 走一遍。闸门该放的放，该拦的拦。
set -u
X="$(cd "$(dirname "$0")" && pwd)/explore"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; mkdir -p "$HOME"
fail=0; expect() { # expect <期望退出码> <说明> <命令…>
  want=$1; what=$2; shift 2; "$@" > "$T/out" 2>&1; got=$?
  if [ $got -eq "$want" ]; then echo "ok    $what"; else echo "FAIL  ${what}（退出码 ${got}，期望 ${want}）"; sed 's/^/      /' "$T/out"; fail=1; fi; }

"$X" selftest > /dev/null || exit 1
git init -q -b main "$T/repo"; cd "$T/repo"
echo 1.0 > speed.txt; echo x > other.txt; echo keep > weights.bin; git add -A; git commit -qm start
git branch explore/base; git worktree add -q "$T/base" explore/base
R=$T/repo/run; "$X" init "$R" > /dev/null
cat > "$R/explore.toml" <<TOML
repo = ".."
branch = "explore/base"
base_worktree = "$T/base"
locked = ["$T/data"]
[commands]
measure = "echo PERF job \$(cat speed.txt) s; echo METRIC exact answer 42 -"
test = "test -f speed.txt"
[rules]
pairs = 2
[[invariants]]
name = "other.txt 没变"
cmd = "cmp other.txt \$EXPLORE_BASE/other.txt"
[[datasets]]
name = "G"
path = "$T/data/g.csv"
role = "final"
TOML
mkdir "$T/data"; echo secret > "$T/data/g.csv"; export EXPLORE_RUN=$R

expect 1 "doctor：没做 A/A 时不过" "$X" doctor --snapshot
expect 0 "aa：同一份代码全部噪声内" "$X" aa
expect 0 "doctor：全过" "$X" doctor

cand() { # cand E### <speed> [多改的文件] -> worktree + 合同 + 评审
  git -C "$T/repo" worktree add -q "$T/$1" -b "explore/$1" explore/base; echo "$2" > "$T/$1/speed.txt"
  [ -n "${3:-}" ] && echo y > "$T/$1/$3"; git -C "$T/$1" commit -qam "$1" --allow-empty
  printf '# %s\n```json\n{"kind":"contract","id":"%s","title":"t","targets":["job"],"predict":{"job":[1.0,0.5]},"allowed":["speed.txt"]}\n```\n' "$1" "$1" > "$R/experiments/$1.md"
  printf '【读到】diff\n```json\n{"kind":"review","target":"%s","sha":"%s","findings":[%s],"checked":["排序"]}\n```\n' "$1" "$(git -C "$T/$1" rev-parse HEAD)" "${4:-}" > "$R/experiments/$1.review.md"; }

cand E001 0.5
expect 0 "land E001：范围内、变快 → 落地" "$X" land E001 "$T/E001"
expect 0 "基线快进到了 E001" test "$(git -C "$T/base" rev-parse HEAD)" = "$(git -C "$T/E001" rev-parse HEAD)"
cand E002 0.2 other.txt
expect 1 "land E002：改了合同外的文件 → 拦" "$X" land E002 "$T/E002"
cand E003 0.5
expect 1 "land E003：没变快 → 拦" "$X" land E003 "$T/E003"
expect 0 "land E003 --owner-ok：记为破例后落地" "$X" land E003 "$T/E003" --owner-ok "所有者同意"
cand E004 0.1 "" '{"where":"a:1","before":"x","after":"y","input":"空输入","blocking":true}'
expect 1 "land E004：评审有挡合并的发现 → 拦" "$X" land E004 "$T/E004"
cand E005 0.1; echo 0.05 > "$T/E005/speed.txt"; git -C "$T/E005" commit -qam fix
expect 1 "land E005：评审之后又改了 → 拦" "$X" land E005 "$T/E005"
cand E006 0.1; echo changed > "$T/data/g.csv"
expect 1 "land E006：locked 路径被动过 → 拦" "$X" land E006 "$T/E006"
"$X" doctor --snapshot > /dev/null; git -C "$T/repo" worktree add -q "$T/old" -b explore/old main
expect 1 "ab：候选有未提交改动 → 不量" sh -c "echo 9 > '$T/old/speed.txt'; '$X' ab '$T/base' '$T/old' --out '$T/m1'"
git -C "$T/old" checkout -q speed.txt
expect 1 "ab：候选变慢 → 回归，退出码 1" "$X" ab "$T/base" "$T/old" --out "$T/m2"
expect 0 "close E002" "$X" close E002 --as 放弃 --why 越界
expect 0 "holdout：第一次" "$X" holdout G --why 终验 -- sh -c 'test -f "$EXPLORE_DATA"'
expect 0 "holdout：第二次有警告" sh -c "'$X' holdout G --why 再看一眼 -- true 2>&1 | grep -q 已经用过"
expect 0 "status：两条落地、一条破例、一条放弃" sh -c "'$X' status | tee '$T/s' | grep -c 接受 | grep -q 2 && grep -q 破例 '$T/s' && grep -q 放弃 '$T/s'"
expect 0 "check：缺字段的提案被退回" sh -c "printf '\`\`\`json\n{\"kind\":\"proposals\",\"items\":[{\"metric\":\"job\"}]}\n\`\`\`\n' > '$T/p.md'; ! '$X' check '$T/p.md'"
[ $fail -eq 0 ] && echo "test ok" || { echo "test FAILED"; exit 1; }
