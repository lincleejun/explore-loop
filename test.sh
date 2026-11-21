#!/bin/bash
# 端到端自检：在临时目录建一个玩具仓库，走 init → aa → new → land。闸门该放的放，该拦的拦，并打印拦下的理由。
set -u
X="$(cd "$(dirname "$0")" && pwd)/explore"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; mkdir -p "$HOME"
fail=0; expect() { # expect <期望退出码> <说明> <命令…>
  want=$1; what=$2; shift 2; "$@" > "$T/out" 2>&1; got=$?
  if [ $got -eq "$want" ]; then echo "ok    ${what}"; [ "$want" -ne 0 ] && grep -m1 '^explore:' "$T/out" | cut -c1-110 | sed 's/^/        /'
  else echo "FAIL  ${what}（退出码 ${got}，期望 ${want}）"; sed 's/^/      /' "$T/out"; fail=1; fi; }
says() { grep -q "$1" "$T/out" || { echo "FAIL  上一条的输出里没有：$1"; sed 's/^/      /' "$T/out"; fail=1; }; }

"$X" selftest > /dev/null || exit 1
git init -q -b main "$T/repo"; cd "$T/repo"
echo 1.0 > speed.txt; echo x > other.txt; echo n > note.txt; echo out.bin > .gitignore
echo 'echo "PERF job $(cat out.bin) s"; echo "METRIC exact answer 42 -"' > measure.sh; git add -A; git commit -qm start
R=$T/camp; B=$T/camp-base; export EXPLORE_RUN=$R   # 战役目录 = 独立分支的 worktree；基线和候选的 worktree 在它旁边
expect 0 "init：一条命令建好战役分支、基线 worktree、配置" "$X" init "$R" --repo "$T/repo" --build "cp speed.txt out.bin" --measure "sh measure.sh" --test "test -f speed.txt"
expect 1 "init：仓库不存在 → 失败，不留下目录" "$X" init "$T/bad" --repo "$T/nonexistent" --measure x --test y; [ -e "$T/bad" ] && { echo "FAIL  留下了目录"; fail=1; }
expect 0 "init：多行命令也能写进配置" sh -c "'$X' init '$T/ml' --repo '$T/repo' --measure 'echo a
echo PERF job 1 s' --test true && python3 -c \"import tomllib,sys; tomllib.loads(open('$T/ml/explore.toml').read())\""
expect 0 "init 之后主检出是干净的" test -z "$(git -C "$T/repo" status --porcelain)"
mkdir "$T/data"; echo secret > "$T/data/g.csv"
python3 - "$R/explore.toml" "$T" <<'PY'
import sys; f, T = sys.argv[1:]; s = open(f).read()
s = s.replace('locked = []', f'locked = ["{T}/data"]').replace('harness = []', 'harness = ["measure.sh"]').replace('busy = ""', f'busy = "cat {T}/busy 2>/dev/null"').replace('pairs = 10', 'pairs = 6')
s += f'\n[[invariants]]\nname = "other.txt 没变"\ncmd = "cmp other.txt $EXPLORE_BASE/other.txt"\n[[datasets]]\nname = "G"\npath = "{T}/data/g.csv"\nrole = "final"\nstrata = "全球"\nleak = "无"\n'
open(f, "w").write(s)
PY
"$X" doctor --snapshot > /dev/null
expect 0 "next：没校准时叫你先校准" "$X" next; says "explore aa"
expect 1 "new：没校准不让开实验" "$X" new t --target job --by claude --allow speed.txt
expect 0 "aa：校准，量出每个指标的噪声" "$X" aa
expect 0 "doctor：全过" "$X" doctor
round() { # 当前基线的一轮：剖析 + 三个调查员各一个主题
  D=$R/rounds/$(git -C "$B" rev-parse HEAD | cut -c1-8); mkdir -p "$D"; for f in profiling claude-io claude-parse codex-alloc; do echo 看过了 > "$D/$f.md"; done; }
preview() { # preview <实验> [评审人] [发现] -> 写提案评审，合同指纹从 next 里取
  "$X" next > "$T/next" 2>&1; H=$(grep "^$1：" "$T/next" | sed -n 's/.*contract 填 \([0-9a-f]*\).*/\1/p'); [ -n "$H" ] || H=$(sed -n 's/.*"contract":"\([0-9a-f]*\)".*/\1/p' "$R/experiments/$1.proposal.review.md")
  printf '合同看过了\n```json\n{"kind":"proposal-review","target":"%s","by":"%s","contract":"%s","findings":[%s]}\n```\n' "$1" "${2:-codex}" "$H" "${3:-}" > "$R/experiments/$1.proposal.review.md"; }
cand() { # cand <速度> [多改的文件] -> 调查、开一个实验、审过提案、提交改动，编号在 $E
  round; "$X" new "t" --target job --by claude-io --allow speed.txt --allow note.txt --predict 0.5 > "$T/new" || { cat "$T/new"; fail=1; }
  E=$(sed -n 's/^\(E[0-9]*\)：.*/\1/p' "$T/new"); W=$R-$E; echo "$1" > "$W/speed.txt"; echo "$E" >> "$W/note.txt"
  [ -n "${2:-}" ] && echo y > "$W/$2"; git -C "$W" commit -qam "$E"; preview $E; }
review() { # review <实验> [发现] -> 写评审文件
  printf 'diff 看过了\n```json\n{"kind":"review","target":"%s","sha":"%s","findings":[%s]}\n```\n' "$1" "$(git -C "$R-$1" rev-parse HEAD)" "${2:-}" > "$R/experiments/$1.review.md"; }

expect 0 "next：没剖析、没调查时说缺什么" "$X" next; says "profiling.md"; says "要 3 份提案"; says "第 1 / 10 轮"
expect 1 "new：这个基线没剖析、没调查 → 不让开实验" "$X" new t --target job --by claude
round; rm "$D/claude-parse.md"
expect 1 "new：提案不够 width 份 → 不让开实验" "$X" new t --target job --by claude-io
round; mv "$D/codex-alloc.md" "$D/claude-alloc.md"
expect 1 "new：配置里的一种代理没参与调查 → 不让开实验" "$X" new t --target job --by claude-io; rm "$D/claude-alloc.md"
round
expect 1 "new：--by 不是这一轮的提案 → 拦" "$X" new t --target job --by claude-nothing
cand 0.5; rm "$R/experiments/$E.proposal.review.md"
expect 0 "next：叫你先找另一个代理审提案" "$X" next; says "请 codex 审合同"
expect 1 "没有提案评审 → 拦" "$X" land $E
preview $E claude
expect 1 "提案人审自己的提案 → 拦" "$X" land $E
preview $E codex '{"where":"合同说缓冲区会涨，代码里它是定长的","blocking":true}'
expect 1 "提案评审有挡开工的发现 → 拦" "$X" land $E
preview $E
expect 0 "next：指出下一条命令" "$X" next; says "explore land $E"
expect 0 "land --dry-run：各步都过，不合并" "$X" land $E --dry-run
expect 0 "land：变快 → 落地，复用 dry-run 的测量" "$X" land $E; says "复用已有的测量"
expect 0 "基线快进到了候选的提交" test "$(git -C "$B" rev-parse HEAD)" = "$(git -C "$R-$E" rev-parse HEAD)"
expect 0 "战役目录可以整个提交" sh -c "git -C '$R' add -A && git -C '$R' commit -qm R01"
expect 1 "落地后基线变了：没重新剖析 → 不让开实验" "$X" new t --target job --by claude-io
sed -i '' 's/^rounds = 10 /rounds = 1  /' "$R/explore.toml"
expect 1 "做满 rounds 轮 → 不让开实验" "$X" new t --target job --by claude-io; says "做满 1 轮"; sed -i '' 's/^rounds = 1  /rounds = 10 /' "$R/explore.toml"
expect 0 "status：第几轮、每轮几个调查员" "$X" status; says "第 2 / 10 轮，每轮 3 个调查员"
cand 0.2 other.txt
expect 1 "改了合同外的文件 → 拦" "$X" land $E
expect 0 "next：说出上次被拦在哪" "$X" next; says "被拦在「改动在合同范围内」"
expect 0 "close：记为放弃" "$X" close $E --as 放弃 --why 越界
cand 0.5
expect 1 "没变快 → 拦" "$X" land $E
expect 0 "--owner-ok：记为破例后落地，不重量" "$X" land $E --owner-ok "所有者同意"; says "复用已有的测量"
cand 0.1; "$X" land $E --dry-run > /dev/null 2>&1; sed -i '' 's/"speed.txt"/"*"/' "$R/experiments/$E.md"
expect 1 "合同改了，提案评审是旧的 → 拦" "$X" land $E; preview $E
expect 1 "过闸门后改合同 → 拦" "$X" land $E
expect 0 "--amend：留痕后放行" "$X" land $E --amend "范围写窄了"
cand 0.05; echo 'echo "PERF job $(cat out.bin) s"' > "$W/measure.sh"; git -C "$W" commit -qam drop; expect 1 "候选改了测量工具 → 拦" "$X" land $E
"$X" close $E --as 拒绝 --why 少了指标 > /dev/null

sed -i '' 's/^strict = false/strict = true /' "$R/explore.toml"   # strict：落地要评审
cand 0.04
expect 1 "strict：没有评审 → 拦" "$X" land $E
expect 0 "strict：dry-run 跳过评审，其余照走" "$X" land $E --dry-run
review $E '{"where":"a:1 空输入时旧代码返回空，新代码崩","blocking":true}'
expect 1 "strict：评审有挡合并的发现 → 拦" "$X" land $E
cp "$R/experiments/$E.md" "$R/experiments/$E.review.md"
expect 1 "strict：评审文件里放的是合同块 → 拦" "$X" land $E
review $E; echo 0.03 > "$W/speed.txt"; git -C "$W" commit -qam fix
expect 1 "strict：评审之后代码又改了 → 拦" "$X" land $E
review $E; git -C "$W" commit -q --amend -m "reword only"
expect 0 "strict：只改提交说明不用重审 → 落地" "$X" land $E

cand 0.02; review $E; echo changed > "$T/data/g.csv"
expect 1 "locked 路径被动过 → 拦" "$X" land $E
"$X" doctor --snapshot > /dev/null; echo "pid 1 xcodebuild" > "$T/busy"
expect 2 "机器上有别的负载 → 不量" "$X" land $E
rm "$T/busy"; echo dirty > "$W/untracked.txt"
expect 1 "候选有未跟踪的文件 → 拦" "$X" land $E
rm "$W/untracked.txt"; sed -i '' 's/measure = "sh measure.sh"/measure = "sh  measure.sh"/' "$R/explore.toml"
expect 1 "测量命令变了 → 旧校准不算数" "$X" land $E
git -C "$T/repo" worktree add -q "$T/slow" -b slow explore/camp-base; echo 9 > "$T/slow/speed.txt"; git -C "$T/slow" commit -qam slow
expect 1 "ab：候选变慢 → 回归，退出码 1" "$X" ab "$B" "$T/slow"
echo 'echo "PERF job 1 s"' > "$B/measure.sh"; git -C "$B" commit -qam "harness: drop a metric"
expect 0 "next：测量工具变了 → 叫你重新校准" "$X" next; says "explore aa"
git -C "$B" reset -q --hard HEAD~1
expect 0 "holdout：第一次" "$X" holdout G --why 终验 -- sh -c 'test -f "$EXPLORE_DATA"'
expect 0 "holdout：第二次有警告" "$X" holdout G --why 再看一眼 -- true; says "已经用过"
expect 0 "status：三条接受、一条破例、一条放弃、一条拒绝" sh -c "'$X' status > '$T/s'; [ \$(grep -c '| 接受' '$T/s') = 4 ] && grep -q 破例 '$T/s' && grep -q 放弃 '$T/s' && grep -q 拒绝 '$T/s'"
expect 0 "power：给出误拦率和检出率" "$X" power --noise 3 --metrics 15 --pairs 10; says "被护栏误拦的概率"
[ $fail -eq 0 ] && echo "test ok" || { echo "test FAILED"; exit 1; }
