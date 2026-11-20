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
expect 0 "init 之后主检出是干净的" test -z "$(git -C "$T/repo" status --porcelain)"
mkdir "$T/data"; echo secret > "$T/data/g.csv"
python3 - "$R/explore.toml" "$T" <<'PY'
import sys; f, T = sys.argv[1:]; s = open(f).read()
s = s.replace('locked = []', f'locked = ["{T}/data"]').replace('busy = ""', f'busy = "cat {T}/busy 2>/dev/null"').replace('pairs = 10', 'pairs = 6')
s += f'\n[[invariants]]\nname = "other.txt 没变"\ncmd = "cmp other.txt $EXPLORE_BASE/other.txt"\n[[datasets]]\nname = "G"\npath = "{T}/data/g.csv"\nrole = "final"\nstrata = "全球"\nleak = "无"\n'
open(f, "w").write(s)
PY
"$X" doctor --snapshot > /dev/null
expect 0 "next：没校准时叫你先校准" "$X" next; says "explore aa"
expect 1 "new：没校准不让开实验" "$X" new t --target job --allow speed.txt
expect 0 "aa：校准，量出每个指标的噪声" "$X" aa
expect 0 "doctor：全过" "$X" doctor
cand() { # cand <速度> [多改的文件] -> 开一个实验并提交改动，编号在 $E
  "$X" new "t" --target job --allow speed.txt --allow note.txt --predict 0.5 > "$T/new" || { cat "$T/new"; fail=1; }
  E=$(sed -n 's/^\(E[0-9]*\)：.*/\1/p' "$T/new"); W=$R-$E; echo "$1" > "$W/speed.txt"; echo "$E" >> "$W/note.txt"
  [ -n "${2:-}" ] && echo y > "$W/$2"; git -C "$W" commit -qam "$E"; }
review() { # review <实验> [发现] -> 写评审文件
  printf '【读到】diff\n```json\n{"kind":"review","target":"%s","sha":"%s","findings":[%s],"checked":["排序"]}\n```\n' "$1" "$(git -C "$R-$1" rev-parse HEAD)" "${2:-}" > "$R/experiments/$1.review.md"; }

cand 0.5
expect 0 "next：指出下一条命令" "$X" next; says "explore land $E"
expect 0 "land --dry-run：各步都过，不合并" "$X" land $E --dry-run
expect 0 "land：变快 → 落地，复用 dry-run 的测量" "$X" land $E; says "复用已有的测量"
expect 0 "基线快进到了候选的提交" test "$(git -C "$B" rev-parse HEAD)" = "$(git -C "$R-$E" rev-parse HEAD)"
expect 0 "战役目录可以整个提交" sh -c "git -C '$R' add -A && git -C '$R' commit -qm R01"
cand 0.2 other.txt
expect 1 "改了合同外的文件 → 拦" "$X" land $E
expect 0 "next：说出上次被拦在哪" "$X" next; says "被拦在「改动在合同范围内」"
expect 0 "close：记为放弃" "$X" close $E --as 放弃 --why 越界
cand 0.5
expect 1 "没变快 → 拦" "$X" land $E
expect 0 "--owner-ok：记为破例后落地，不重量" "$X" land $E --owner-ok "所有者同意"; says "复用已有的测量"
cand 0.1; "$X" land $E --dry-run > /dev/null 2>&1; sed -i '' 's/"speed.txt"/"*"/' "$R/experiments/$E.md"
expect 1 "过闸门后改合同 → 拦" "$X" land $E
expect 0 "--amend：留痕后放行" "$X" land $E --amend "范围写窄了"
cand 0.05; echo 'echo "PERF job $(cat out.bin) s"' > "$W/measure.sh"; git -C "$W" commit -qam drop; sed -i '' 's/"note.txt"/"note.txt","measure.sh"/' "$R/experiments/$E.md"
expect 1 "候选让一个指标消失 → 不判" "$X" land $E
"$X" close $E --as 拒绝 --why 少了指标 > /dev/null

sed -i '' 's/^strict = false/strict = true /' "$R/explore.toml"   # strict：落地要评审
cand 0.04
expect 1 "strict：没有评审 → 拦" "$X" land $E
expect 0 "strict：dry-run 跳过评审，其余照走" "$X" land $E --dry-run
review $E '{"where":"a:1","before":"x","after":"y","input":"空输入","blocking":true}'
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
expect 0 "holdout：第一次" "$X" holdout G --why 终验 -- sh -c 'test -f "$EXPLORE_DATA"'
expect 0 "holdout：第二次有警告" "$X" holdout G --why 再看一眼 -- true; says "已经用过"
expect 0 "status：三条接受、一条破例、一条放弃、一条拒绝" sh -c "'$X' status > '$T/s'; [ \$(grep -c '| 接受' '$T/s') = 4 ] && grep -q 破例 '$T/s' && grep -q 放弃 '$T/s' && grep -q 拒绝 '$T/s'"
expect 0 "power：给出误拦率和检出率" "$X" power --noise 3 --metrics 15 --pairs 10; says "被护栏误拦的概率"
expect 0 "check：缺字段的提案被退回" sh -c "printf '\`\`\`json\n{\"kind\":\"proposals\",\"items\":[{\"metric\":\"job\"}]}\n\`\`\`\n' > '$T/p.md'; ! '$X' check '$T/p.md'"
[ $fail -eq 0 ] && echo "test ok" || { echo "test FAILED"; exit 1; }
