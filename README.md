# explore-loop

A measured improvement loop for agents: profile the baseline, investigate in parallel, have a different agent review each proposal, then verify. `explore` refuses to open or land an experiment until those records exist; it measures the candidate against the baseline in pairs, decides *better / regression / inconclusive*, lands only what passes, and logs every attempt.

```sh
explore init ~/wt/demo --repo <repo> --measure '<command that prints metric lines>' --test '<test command>' --rounds 10 --width 3   # depth: rounds; width: investigators per round
cd ~/wt/demo
explore aa                                  # calibrate: each metric's noise
explore next                                # one round per new baseline: profile -> investigators propose in parallel -> a different agent reviews each proposal
explore new "<idea>" --target "<metric>" --by <proposal>   # an id, a one-page record, a worktree
explore land E001                           # verify; merged into the baseline if it passes, otherwise it says where it was blocked
```

The full instructions are in [`SKILL.md`](SKILL.md): how a round goes, what you have to supply, how verification works, the data behind the verdict rule, what the tool cannot do.

## What is in here

| File | What it is |
|---|---|
| `explore` | The whole tool. One Python file, 3.11+, standard library only, tied to no agent framework |
| `SKILL.md` | The instructions agents read. It has the frontmatter of a Claude Code skill; the body is plain Markdown |
| `templates/` | The templates `explore init` and `explore new` use |
| `test.sh` | End-to-end check: walks the whole flow in a temporary repository; what must be blocked is blocked |
| `codex.sh` | Has Codex act as a read-only investigator or reviewer (for when `[agents]` lists `codex`) |

## Install

- **Command line**: `npm install -g explore-loop` (needs Python 3.11+ on the system), or clone and put `explore` on your `PATH`.
- **Claude Code skill**: `git clone https://github.com/lincleejun/explore-loop ~/.claude/skills/explore-loop`. Update with `git pull`.
- **pi**: `pi install git:github.com/lincleejun/explore-loop`, or `pi install npm:explore-loop` (the repository is itself a pi package; `package.json` declares the skill). Then `/skill:explore-loop`, or let the model load it from the description.
- **Any agent (Codex, pi, Cursor…)**: link `explore` into your `PATH` (`ln -s $PWD/explore ~/.local/bin/explore`), then add two lines to the project's `AGENTS.md`:

  ```
  To verify that a change really improves a metric, use `explore`. The first time, run `explore guide` to read the instructions; after that, `explore next` says what to do next.
  Exit codes: 0 done, 1 blocked (the reason is in the output), 2 the measurement is void, retry later.
  ```

  The tool carries its own instructions (`explore guide`) and says the next step itself (`explore next`), so an agent needs no dedicated plugin. The ledger is `ledger.jsonl`, one JSON object per line, readable directly.

## Self-check

```sh
./explore selftest && ./test.sh
```

Do not pipe them into anything: a pipe swallows the exit code.

The verdict rule draws on benchstat, criterion.rs and asv.

MIT License.
