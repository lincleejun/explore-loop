---
name: explore-loop
description: Run a measured improvement loop on any project (speed, accuracy, memory, size). Each round profiles the accepted baseline, sends several read-only investigator agents in parallel, has a different agent review each proposal, then implements in isolated worktrees; the tool measures candidate against baseline in pairs, decides better / regression / inconclusive, lands only what passes, and logs every attempt. Use when asked to optimize or tune something measurable, to "explore", to run an exploration loop or multi-round experiments, or to resume / audit such work.
---

# explore-loop

**Each round: profile the baseline → several investigators propose in parallel → a different agent reviews each proposal → implement in isolated lanes → the tool verifies.**
What to propose and how long the records are is up to you. Profiling, investigation and proposal review must have happened: the tool opens no experiment and lands nothing until it sees the records. A change that claims to help has to be measured before it counts.

The tool is `./explore` in this directory (Python 3.11+, standard library only).

```sh
explore init ~/wt/<name> --repo <repo> --measure '<command that prints metric lines>' --test '<test command>' [--build '<build command>'] [--rounds 10] [--width 3]
cd ~/wt/<name>
explore aa                                  # calibrate once: how noisy each metric is
explore next                                # what this round still lacks: the profile, which investigator has not reported, which contract is not reviewed
explore new "<idea>" --target "<metric>" --by <proposal>   # gives you an id, a one-page record, a worktree
explore land E001                           # verify; merged into the baseline if it passes, otherwise it says where it was blocked
```

## A round

```
accepted baseline ──profile──▶ investigators (read-only, in parallel) ──proposals──▶ lead: picks proposals, writes contracts
     ──▶ proposal review (a different agent) ──▶ verifiers (one worktree each, in parallel): implement, self-check, commit
     ──▶ explore land ──▶ landed patches advance the baseline, which is profiled again; every result (failures too) goes on the ledger for the next proposals
```

**The owner decides depth and width; ask before starting** (use the defaults if they do not say). They live in `[loop]` in `explore.toml`:

- `rounds`, the depth: how many rounds to run. Default 10. When they are done the tool opens no more experiments; close out and write the report.
- `width`, the width: how many investigators go out per round, each on a different topic. Default 3, usually 3–5; more when the codebase is big or the profile shows scattered hot spots.

Who investigates and who reviews proposals is configured in `[agents]`. A name is an agent you can dispatch: a subagent type, a different model, an external tool (`codex` goes through `codex.sh` in this directory).
Topics come from the profile each round (for example: parsing, IO, memory allocation, concurrency, the algorithm itself), one per investigator, not overlapping; one kind of agent may take several topics.

| Step | Who | Hands in | How the tool blocks |
|---|---|---|---|
| Profile | The lead (the main session) | `rounds/<base>/profiling.md`: where the baseline's time or errors go, with the commands that produce the numbers; it ends with this round's `width` investigation topics | Without it, no `new` |
| Investigate | `width` investigators, sent in parallel in one message, read-only; at least one of every kind in `agents.investigate` | `rounds/<base>/<agent>-<topic>.md`: the mechanism (file:line), the evidence, the prediction of which metric goes from what to what; if nothing is worth doing, say so with evidence | Fewer than `width` files, or a kind of agent that is absent, means no `new`; `--by` takes the proposal's file name |
| Proposal review | One of `agents.review`, not the proposer | `experiments/E###.proposal.review.md`, ending in a block (see below) | No `land` if it is missing, is of another version of the contract, was written by the proposer, or has a blocking finding |
| Implement | Verifiers, one worktree per experiment; implementation may run in parallel, the tool queues measurements | A commit | `land` |
| Decide | `explore land` | A row on the ledger | |

Open all of a round's experiments (`explore new`) before the first one lands. Once the baseline moves, the tool opens no new experiment: finish the open ones (those that land merge the new baseline and are measured again; close the rest), then profile and investigate the new baseline once, in a new directory under `rounds/`.

- **The brief for an investigator** includes: the campaign directory (`profile.md`, `ledger.md`), the output of `explore status`, this round's `profiling.md`, and the one topic it owns. Different topics are what keep them from handing in the same thing.
- **What the proposal review asks**: is this a general mechanism, or does it work only on the benchmark's fixtures and data; has the same mechanism been tried according to the ledger, and does the old reason for failure still hold; are the code and the numbers the contract cites right when you check them yourself; is the prediction larger than what `explore power` says can be seen; which behavior that must not change is missing.
  The block: `{"kind":"proposal-review","target":"E001","by":"<reviewer>","contract":"<the fingerprint explore next gives>","findings":[{"where":"…","blocking":true}]}`. A changed contract needs a new review.
- **The lead writes no product code** and does not merge around `land`. A proposer who accepts its own proposal is not an honest acceptance.

`explore next` says where things are stuck; `explore status` is the ledger; `explore close E001 --as abandoned|rejected|redirected --why …` closes what did not work;
`explore power` says how big a change can be seen at your noise.

## What the tool needs from you

- **Metric lines**. The measure command prints `PERF <name> <number> <s|ms>`, or `METRIC <lower|higher|exact> <name> <value> <unit>` (use higher for accuracy, exact for checksums).
- **A target**. `--target` of `new`: which metric this idea should improve. Every other metric becomes a guard.
- **A clean commit**. A candidate is measured only once it is committed; files left by the build and the tests must be in `.gitignore`.
- Everything else is optional: `--allow` limits the files that may change, `--predict` records a prediction to score afterwards, and `explore.toml` takes invariant commands, locked paths and holdout sets.

`init` does not touch the main checkout: it creates two branches and two worktrees. `~/wt/<name>/` holds the records (commit it whenever), `~/wt/<name>-base/` is the baseline, and candidates are in `~/wt/<name>-E001/`.

## How the tool verifies

1. The candidate is a clean commit that contains the current baseline and changes only the files it declared; the tests and the invariants pass.
2. Baseline and candidate are measured in pairs (10 by default, the order balanced every two pairs, one lock for the whole machine, void if the machine is busy).
3. A metric counts as changed only if both hold: the direction is significant (exact sign test, corrected for the number of metrics), and the median of the paired differences is beyond a threshold.
   For a target the threshold is `min_gain`; for a guard it is the largest of `guard`%, `floor` and the calibrated noise.
   Only one thing is guaranteed statistically: when nothing changed, the probability that noise misjudges a landing is at most `alpha`. The median threshold is an engineering filter on size;
   when the real change sits right at the threshold (4.9% slower with a 5% tolerance) it can go either way.
4. Targets better and no guard regressed → fast-forward merge, logged. Otherwise a "blocked" row is logged. After measuring, both sides are checked again to be the same commits.

The same commits are not measured twice (measuring again needs a written reason), the target in a record cannot be changed quietly once it has passed the gate, and every blocked attempt stays on the ledger.
The owner can make an exception: `--owner-ok "<their words>"`, marked on the ledger.

The data behind this rule (15 metrics, reproducible with `explore power`):

| Spread of a single measurement | Pairs | Blocked when nothing changed | Target 5% faster is seen | 10% faster is seen | Guard 10% slower is blocked |
|---|---|---|---|---|---|
| 3% | 10 | 0.0% | 29% | 91% | 89% |
| 3% | 20 | 0.0% | 80% | 100% | 99% |
| 8% | 20 | 0.0% | 7% | 47% | 0% (the noise raises the tolerance to about 19%) |

The table simulates independent normal noise; real drift and cache state only make it worse. With 15 metrics and 10 pairs, all 10 pairs must agree to be significant; 20 pairs leave room for 3 that disagree.
The first experiment costs 40 single-side measurements including calibration, each later one 20. Fix the number of pairs before looking at results; do not measure until it is significant.
"Inconclusive" is not "no regression". A noisy metric cannot serve as a guard, and `explore aa` names those; to see small changes, raise `pairs` or make the measurement steadier first.
"Significance plus a minimum size" comes from criterion.rs and asv (they use other tests); at least 10 runs and alternating measurements come from benchstat.
The first version of the rule, now replaced (4 samples a side, an 85% win line), blocked about 16% of landings on pure noise under the same conditions.

## When you want it stricter

- `strict = true` in `explore.toml`: besides the proposal review, landing also needs a review of this very code, written to `experiments/E###.review.md` and ending in a block:
  `{"kind":"review","target":"E001","sha":"<the reviewed commit>","findings":[{"where":"…","blocking":true}]}`. A blocking finding means no landing; changed code needs a new review.
  Who reviews is up to you; a different model, without the context of the implementation, most easily sees a behavior change the tests do not cover.
- Tuning and accuracy work: register what each dataset is for in `explore.toml`, keep the holdout set outside the repository, and use it only through `explore holdout`, which logs every use.

## What the tool cannot do

- It guards against carelessness, not against cheating: whether the profile and the proposals were really made by that agent, who wrote a review, who spoke the words of an exception, it does not know. It only leaves a trace.
- The proposal review is checked only at `land`: review before implementation is the order `explore next` reminds you of, not something it enforces. The fingerprint covers only the contract's json block, so a change to the mechanism or the evidence in the body does not ask for a new review.
- A holdout set cannot be protected from being read; `locked` only compares file sizes and modification times at landing.
- Only "one repository, candidates are its worktrees" is supported. The measure command runs in each worktree: list the harness's files under `harness` in `explore.toml`
  and candidates may not change them; to change them, commit to the campaign branch directly and calibrate again.
- When the measured environment is not the product (a simulator, small inputs, a dev machine), discount the conclusions in the report.

## Worth knowing from the first campaigns

Not rules. These are places where someone has already paid for the lesson.

- The biggest gain often comes from reading the code before starting and finding that the premise is wrong; a frame that vanishes from the profile does not mean faster, so trust only end-to-end numbers.
- An all-green benchmark only says that what the benchmark covers did not change. What a fast path loses most easily is failure behavior the old code had implicitly.
- Special-casing the benchmark's names, fixtures or known answers is something a loop learns sooner or later; so ask "does this still hold on other data".
- Test the judge first: run `explore ab` once on a commit that is known to be worse. If it cannot call the regression, this measurement cannot judge that direction; fix it first.
- "Inconclusive" holds only for the data that was measured. An idea that is not significant on an eval set covering one region or one size may be the biggest gain on another distribution;
  when you close it with `--as abandoned`, write "on which data" into `--why`.
- A switch that is off by default can go through the gate too: turn it on in the measure command (the baseline does not know the variable), and add an invariant "output is bit-identical when it is unset".
  After it lands, note in `ledger.md` that "on by default waits for the owner's decision", or the ledger cannot tell it from an output-equivalent change.
- Experiments that failed are as useful as those that worked: read `explore status` before proposing the next idea.
- When tests pass, look at the number skipped; a cache key needs a fingerprint of the upstream code; load average does not show a busy GPU.
- Do not pipe the measure and test commands into anything: a pipe swallows the exit code.

## Closing out

Before stopping (all `rounds` done, the owner calls a halt, a round with no landing): look in `explore status` at the metrics that were never a target and say in the report why they were not examined;
use the holdout set once, only now, and write the result back if it contradicts an experiment that was closed; give one sentence each to how the measured environment differs from the product and to the paths that were reviewed as code but never measured.

To change this skill: `./explore selftest` and `./test.sh` must both pass.
