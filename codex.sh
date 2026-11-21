#!/bin/zsh
# Have Codex look at a repository read-only and answer a brief; the answer goes to a file. Investigators and reviews both go through here.
# Usage: codex.sh <repository path> <brief file> <answer output file>
set -eu
repo=${1:?usage: codex.sh <repository> <brief file> <output file>}; brief=${2:?}; out=${3:?}
mkdir -p "$(dirname "$out")"
# -s read-only: Codex cannot change the repository. Its answer is an opinion, not an instruction.
codex exec -s read-only --skip-git-repo-check -C "$repo" -o "$out" - < "$brief" > "${out%.*}.log" 2>&1
