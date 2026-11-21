#!/bin/bash
# End-to-end check: build a toy repository in a temp directory and walk init -> aa -> new -> land.
# The gate must pass what should pass, block what should be blocked, and print why it blocked.
set -u
X="$(cd "$(dirname "$0")" && pwd)/explore"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t; mkdir -p "$HOME"
fail=0; expect() { # expect <wanted exit code> <description> <command…>
  want=$1; what=$2; shift 2; "$@" > "$T/out" 2>&1; got=$?
  if [ $got -eq "$want" ]; then echo "ok    ${what}"; [ "$want" -ne 0 ] && grep -m1 '^explore:' "$T/out" | cut -c1-110 | sed 's/^/        /'
  else echo "FAIL  ${what} (exit code ${got}, wanted ${want})"; sed 's/^/      /' "$T/out"; fail=1; fi; }
says() { grep -q "$1" "$T/out" || { echo "FAIL  the previous output does not contain: $1"; sed 's/^/      /' "$T/out"; fail=1; }; }

"$X" selftest > /dev/null || exit 1
git init -q -b main "$T/repo"; cd "$T/repo"
echo 1.0 > speed.txt; echo x > other.txt; echo n > note.txt; echo out.bin > .gitignore
echo 'echo "PERF job $(cat out.bin) s"; echo "METRIC exact answer 42 -"' > measure.sh; git add -A; git commit -qm start
R=$T/camp; B=$T/camp-base; export EXPLORE_RUN=$R   # campaign directory = worktree of a separate branch; baseline and candidate worktrees sit next to it
expect 0 "init: one command creates the campaign branch, the baseline worktree and the config" "$X" init "$R" --repo "$T/repo" --build "cp speed.txt out.bin" --measure "sh measure.sh" --test "test -f speed.txt"
expect 1 "init: the repository does not exist -> fails and leaves no directory" "$X" init "$T/bad" --repo "$T/nonexistent" --measure x --test y; [ -e "$T/bad" ] && { echo "FAIL  a directory was left behind"; fail=1; }
expect 0 "init: a multi-line command fits in the config too" sh -c "'$X' init '$T/ml' --repo '$T/repo' --measure 'echo a
echo PERF job 1 s' --test true && python3 -c \"import tomllib,sys; tomllib.loads(open('$T/ml/explore.toml').read())\""
expect 0 "the main checkout is clean after init" test -z "$(git -C "$T/repo" status --porcelain)"
mkdir "$T/data"; echo secret > "$T/data/g.csv"
python3 - "$R/explore.toml" "$T" <<'PY'
import sys; f, T = sys.argv[1:]; s = open(f).read()
s = s.replace('locked = []', f'locked = ["{T}/data"]').replace('harness = []', 'harness = ["measure.sh"]').replace('busy = ""', f'busy = "cat {T}/busy 2>/dev/null"').replace('pairs = 10', 'pairs = 6')
s += f'\n[[invariants]]\nname = "other.txt unchanged"\ncmd = "cmp other.txt $EXPLORE_BASE/other.txt"\n[[datasets]]\nname = "G"\npath = "{T}/data/g.csv"\nrole = "final"\nstrata = "global"\nleak = "none"\n'
open(f, "w").write(s)
PY
"$X" doctor --snapshot > /dev/null
expect 0 "next: tells you to calibrate first" "$X" next; says "explore aa"
expect 1 "new: no experiment before calibration" "$X" new t --target job --by claude --allow speed.txt
expect 0 "aa: calibrates and reports each metric's noise" "$X" aa
expect 0 "doctor: all fine" "$X" doctor
round() { # one round on the current baseline: the profile + three investigators, one topic each
  D=$R/rounds/$(git -C "$B" rev-parse HEAD | cut -c1-8); mkdir -p "$D"; for f in profiling claude-io claude-parse codex-alloc; do echo looked > "$D/$f.md"; done; }
preview() { # preview <experiment> [reviewer] [finding] -> write the proposal review; the contract fingerprint comes from next
  "$X" next > "$T/next" 2>&1; H=$(grep "^$1: " "$T/next" | sed -n 's/.*contract is \([0-9a-f]*\).*/\1/p'); [ -n "$H" ] || H=$(sed -n 's/.*"contract":"\([0-9a-f]*\)".*/\1/p' "$R/experiments/$1.proposal.review.md")
  printf 'read the contract\n```json\n{"kind":"proposal-review","target":"%s","by":"%s","contract":"%s","findings":[%s]}\n```\n' "$1" "${2:-codex}" "$H" "${3:-}" > "$R/experiments/$1.proposal.review.md"; }
cand() { # cand <speed> [extra file to change] -> investigate, open an experiment, get the proposal reviewed, commit the change; the id is in $E
  round; "$X" new "t" --target job --by claude-io --allow speed.txt --allow note.txt --predict 0.5 > "$T/new" || { cat "$T/new"; fail=1; }
  E=$(sed -n 's/^\(E[0-9]*\): .*/\1/p' "$T/new"); W=$R-$E; echo "$1" > "$W/speed.txt"; echo "$E" >> "$W/note.txt"
  [ -n "${2:-}" ] && echo y > "$W/$2"; git -C "$W" commit -qam "$E"; preview $E; }
review() { # review <experiment> [finding] -> write the code review file
  printf 'read the diff\n```json\n{"kind":"review","target":"%s","sha":"%s","findings":[%s]}\n```\n' "$1" "$(git -C "$R-$1" rev-parse HEAD)" "${2:-}" > "$R/experiments/$1.review.md"; }

expect 0 "next: says what is missing when nothing is profiled or investigated" "$X" next; says "profiling.md"; says "3 proposals are needed"; says "round 1 / 10"
expect 1 "new: baseline not profiled or investigated -> no experiment" "$X" new t --target job --by claude
round; rm "$D/claude-parse.md"
expect 1 "new: fewer than width proposals -> no experiment" "$X" new t --target job --by claude-io
round; mv "$D/codex-alloc.md" "$D/claude-alloc.md"
expect 1 "new: a configured agent did not investigate -> no experiment" "$X" new t --target job --by claude-io; rm "$D/claude-alloc.md"
round
expect 1 "new: --by is not a proposal of this round -> blocked" "$X" new t --target job --by claude-nothing
cand 0.5; rm "$R/experiments/$E.proposal.review.md"
expect 0 "next: tells you to get a different agent to review the proposal first" "$X" next; says "ask codex to review the contract"
expect 1 "no proposal review -> blocked" "$X" land $E
preview $E claude
expect 1 "the proposer reviews its own proposal -> blocked" "$X" land $E
preview $E codex '{"where":"the contract says the buffer grows; in the code it has a fixed size","blocking":true}'
expect 1 "the proposal review has a blocking finding -> blocked" "$X" land $E
preview $E
expect 0 "next: names the next command" "$X" next; says "explore land $E"
expect 0 "land --dry-run: every step passes, nothing is merged" "$X" land $E --dry-run
expect 0 "land: faster -> lands, reusing the dry-run measurement" "$X" land $E; says "reusing the existing measurement"
expect 0 "the baseline fast-forwarded to the candidate's commit" test "$(git -C "$B" rev-parse HEAD)" = "$(git -C "$R-$E" rev-parse HEAD)"
expect 0 "the whole campaign directory can be committed" sh -c "git -C '$R' add -A && git -C '$R' commit -qm R01"
expect 1 "the baseline moved after landing: not profiled again -> no experiment" "$X" new t --target job --by claude-io
sed -i '' 's/^rounds = 10 /rounds = 1  /' "$R/explore.toml"
expect 1 "all rounds done -> no experiment" "$X" new t --target job --by claude-io; says "all 1 rounds are done"; sed -i '' 's/^rounds = 1  /rounds = 10 /' "$R/explore.toml"
expect 0 "status: which round, how many investigators per round" "$X" status; says "round 2 / 10, 3 investigators per round"
cand 0.2 other.txt
expect 1 "a file outside the contract changed -> blocked" "$X" land $E
expect 0 "next: says where it was blocked last time" "$X" next; says "last blocked at \"the change is within the contract's scope\""
expect 0 "close: recorded as abandoned" "$X" close $E --as abandoned --why "out of scope"
cand 0.5
expect 1 "not faster -> blocked" "$X" land $E
expect 0 "--owner-ok: lands as an exception without measuring again" "$X" land $E --owner-ok "the owner agreed"; says "reusing the existing measurement"
cand 0.1; "$X" land $E --dry-run > /dev/null 2>&1; sed -i '' 's/"speed.txt"/"*"/' "$R/experiments/$E.md"
expect 1 "the contract changed and the proposal review is stale -> blocked" "$X" land $E; preview $E
expect 1 "the contract changed after passing the gate -> blocked" "$X" land $E
expect 0 "--amend: logged, then let through" "$X" land $E --amend "the scope was too narrow"
cand 0.05; echo 'echo "PERF job $(cat out.bin) s"' > "$W/measure.sh"; git -C "$W" commit -qam drop; expect 1 "the candidate changed the harness -> blocked" "$X" land $E
"$X" close $E --as rejected --why "a metric went missing" > /dev/null

sed -i '' 's/^strict = false/strict = true /' "$R/explore.toml"   # strict: landing also needs a code review
cand 0.04
expect 1 "strict: no code review -> blocked" "$X" land $E
expect 0 "strict: dry-run skips the code review and runs the rest" "$X" land $E --dry-run
review $E '{"where":"a:1 on empty input the old code returns empty, the new code crashes","blocking":true}'
expect 1 "strict: the code review has a blocking finding -> blocked" "$X" land $E
cp "$R/experiments/$E.md" "$R/experiments/$E.review.md"
expect 1 "strict: the review file holds a contract block -> blocked" "$X" land $E
review $E; echo 0.03 > "$W/speed.txt"; git -C "$W" commit -qam fix
expect 1 "strict: the code changed after the review -> blocked" "$X" land $E
review $E; git -C "$W" commit -q --amend -m "reword only"
expect 0 "strict: rewording the commit message needs no new review -> lands" "$X" land $E

cand 0.02; review $E; echo changed > "$T/data/g.csv"
expect 1 "a locked path was touched -> blocked" "$X" land $E
"$X" doctor --snapshot > /dev/null; echo "pid 1 xcodebuild" > "$T/busy"
expect 2 "other load on the machine -> no measurement" "$X" land $E
rm "$T/busy"; echo dirty > "$W/untracked.txt"
expect 1 "the candidate has an untracked file -> blocked" "$X" land $E
rm "$W/untracked.txt"; sed -i '' 's/measure = "sh measure.sh"/measure = "sh  measure.sh"/' "$R/explore.toml"
expect 1 "the measure command changed -> the old calibration no longer counts" "$X" land $E
git -C "$T/repo" worktree add -q "$T/slow" -b slow explore/camp-base; echo 9 > "$T/slow/speed.txt"; git -C "$T/slow" commit -qam slow
expect 1 "ab: slower candidate -> regression, exit code 1" "$X" ab "$B" "$T/slow"
echo 'echo "PERF job 1 s"' > "$B/measure.sh"; git -C "$B" commit -qam "harness: drop a metric"
expect 0 "next: the harness changed -> tells you to calibrate again" "$X" next; says "explore aa"
git -C "$B" reset -q --hard HEAD~1
expect 0 "holdout: first use" "$X" holdout G --why "final check" -- sh -c 'test -f "$EXPLORE_DATA"'
expect 0 "holdout: the second use warns" "$X" holdout G --why "one more look" -- true; says "has been used 1 times already"
echo '{"time":"t","id":"E900","title":"old ledger row","status":"放弃","why":"x"}' >> "$R/ledger.jsonl"
expect 0 "status: four accepted, one exception, abandoned, rejected; old Chinese statuses still read" sh -c "'$X' status > '$T/s'; [ \$(grep -c '| accepted' '$T/s') = 4 ] && grep -q '(exception)' '$T/s' && [ \$(grep -c '| abandoned' '$T/s') = 2 ] && grep -q '| rejected' '$T/s'"
expect 0 "power: gives the false-block rate and the detection rates" "$X" power --noise 3 --metrics 15 --pairs 10; says "probability that a guard blocks"
[ $fail -eq 0 ] && echo "test ok" || { echo "test FAILED"; exit 1; }
